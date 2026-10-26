import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart' show NdefAndroid;
import 'package:nfc_manager/nfc_manager_ios.dart' show NdefIos;
import 'package:wifi_iot/wifi_iot.dart';

import '../platforms/rtc_link_platform.dart';
import 'protocomm.dart';
import 'provisioning.dart';

/// ESP32 provisioning service UUID. / ESP32 配网服务 UUID。
const String kEspProvisioningServiceUuid =
    '021a9004-0382-4aea-bff4-6b3f1c5adfb4';

/// Default protocomm endpoint map. / 默认 protocomm 端点映射。
const Map<String, String> kEspProvisioningEndpoints = <String, String>{
  'prov-scan': 'ff50',
  'prov-session': 'ff51',
  'prov-config': 'ff52',
  'proto-ver': 'ff53',
  'custom-data': 'ff54',
};

/// BLE transport for ESP32 protocomm (implements [ProtocommTransport] over
/// `flutter_blue_plus`). / ESP32 protocomm 的 BLE 传输（基于
/// `flutter_blue_plus` 实现 [ProtocommTransport]）。
class EspBleTransport implements ProtocommTransport {
  EspBleTransport(
    this.device, {
    this.serviceUuid = kEspProvisioningServiceUuid,
    this.endpointTable = kEspProvisioningEndpoints,
    this.license = License.nonprofit,
  });

  final BluetoothDevice device;
  final String serviceUuid;
  final Map<String, String> endpointTable;

  /// flutter_blue_plus license declaration (commercial use needs the paid
  /// license). / flutter_blue_plus 许可声明（商业用途需购买付费许可）。
  final License license;

  late final Map<String, BluetoothCharacteristic> _characteristics;

  @override
  Future<bool> connect() async {
    await disconnect();
    try {
      await device.connect(license: license, autoConnect: false, mtu: 256);
      final services = await device.discoverServices();
      _cacheCharacteristics(services);
    } catch (_) {
      return false;
    }
    return device.isConnected;
  }

  @override
  Future<bool> checkConnect() async => device.isConnected;

  @override
  Future<bool> disconnect() async {
    if (!device.isConnected) return true;
    try {
      await device.disconnect();
    } catch (_) {
      return false;
    }
    return true;
  }

  @override
  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    final characteristic = _characteristics[epName];
    if (characteristic == null) {
      throw StateError('Characteristic not found for endpoint: $epName');
    }
    if (data.isNotEmpty) {
      await characteristic.write(data.toList(), withoutResponse: false);
    }
    final response = await characteristic.read();
    return Uint8List.fromList(response);
  }

  void _cacheCharacteristics(List<BluetoothService> services) {
    _characteristics = <String, BluetoothCharacteristic>{};
    final targets = <String, String>{};
    for (final entry in endpointTable.entries) {
      targets[_buildCharUuid(entry.value)] = entry.key;
    }
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final endpoint = targets[characteristic.uuid.toString().toLowerCase()];
        if (endpoint != null) {
          _characteristics[endpoint] = characteristic;
        }
      }
    }
  }

  String _buildCharUuid(String endpointHex) {
    final hex = int.parse(
      endpointHex,
      radix: 16,
    ).toRadixString(16).padLeft(4, '0');
    return '${serviceUuid.substring(0, 4)}$hex${serviceUuid.substring(8)}';
  }
}

/// BLE provisioning channel (scan + provision via `esp_provisioning_ble`).
/// BLE 配网通道（扫描 + 经 `esp_provisioning_ble` 配网）。
class EspBleProvisioningChannel implements BleProvisioningChannel {
  EspBleProvisioningChannel({
    this.serviceUuid = kEspProvisioningServiceUuid,
    this.license = License.nonprofit,
    this.pop,
  });

  final String serviceUuid;
  final License license;

  /// Proof of Possession for the device (device-specific, never hardcoded).
  /// 设备的所有权证明（按设备而变，严禁硬编码）。
  final String? pop;

  @override
  Future<List<ProvisionDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final found = <String, ProvisionDevice>{};
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        found[id] = ProvisionDevice(
          id: id,
          name: result.device.platformName.isNotEmpty
              ? result.device.platformName
              : result.advertisementData.advName.isNotEmpty
              ? result.advertisementData.advName
              : id,
          capabilities: const <ProvisionMethod>{ProvisionMethod.ble},
          rssi: result.rssi,
          platformDevice: result.device,
        );
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: <Guid>[Guid(serviceUuid)],
        timeout: timeout,
      );
      // Drop the replayed results of the previous scan (same reason as in
      // BleScanner). / 丢弃上一次扫描的回放结果（原因同 BleScanner）。
      found.clear();
      await Future<void>.delayed(timeout + const Duration(milliseconds: 300));
    } finally {
      // Always release the scan: startScan throws when Bluetooth is off or a
      // permission is missing, which would otherwise leak the subscription. /
      // 始终释放扫描：蓝牙关闭或缺少权限时 startScan 会抛异常，否则会泄漏订阅。
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
    return found.values.toList();
  }

  @override
  Future<bool> provision(ProvisionDevice device, WifiCredential wifi) async {
    final bluetoothDevice = device.platformDevice;
    if (bluetoothDevice is! BluetoothDevice) return false;
    final transport = EspBleTransport(
      bluetoothDevice,
      serviceUuid: serviceUuid,
      license: license,
    );
    final prov = EspProtocomm(
      transport: transport,
      security: ProtocommSecurity1(pop: pop),
    );
    try {
      if (!await prov.establishSession()) return false;
      final configured = await prov.sendWifiConfig(
        ssid: wifi.ssid,
        password: wifi.password,
        bssid: wifi.bssid,
      );
      if (!configured) return false;
      await prov.applyWifiConfig();
      // The device needs several seconds to associate: a single status read
      // right after applying almost always reports "connecting", which used to
      // be mis-reported as rejected credentials. /
      // 设备需要数秒完成关联：应用配置后立刻读一次状态几乎总是返回 connecting，
      // 过去会被误报为凭据被拒绝。
      return await _waitForConnection(prov);
    } finally {
      await prov.dispose();
    }
  }

  /// Polls the provisioning status until the device reaches a terminal state.
  /// 轮询配网状态直到设备进入终态。
  Future<bool> _waitForConnection(
    EspProtocomm prov, {
    Duration timeout = const Duration(seconds: 20),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await prov.getStatus();
      switch (status.state) {
        case ProvisionConnectionState.connected:
          return true;
        case ProvisionConnectionState.authError:
        case ProvisionConnectionState.networkNotFound:
        case ProvisionConnectionState.connectionFailed:
          return false;
        case ProvisionConnectionState.connecting:
        case ProvisionConnectionState.disconnected:
          await Future<void>.delayed(interval);
      }
    }
    return false;
  }
}

/// DPP provisioning channel (Android-only via the plugin's platform channel).
/// DPP 配网通道（经插件平台通道，仅 Android）。
class DppProvisioningChannelImpl implements DppProvisioningChannel {
  const DppProvisioningChannelImpl();

  @override
  Future<bool> provision({required String qrContent}) =>
      RtcLinkPlatform.instance.startDppConfigurator(qrContent);
}

/// NFC provisioning channel (NDEF credential tags). / NFC 配网通道（NDEF 凭据标签）。
class NfcProvisioningChannelImpl implements NfcProvisioningChannel {
  const NfcProvisioningChannelImpl();

  @override
  Future<WifiCredential?> readCredentialTag({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<WifiCredential?>();
    Timer? timeoutTimer;
    await NfcManager.instance.startSession(
      pollingOptions: const <NfcPollingOption>{
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (tag) async {
        final message = await _readNdefMessage(tag);
        final credential = message == null ? null : _parseCredential(message);
        if (!completer.isCompleted) completer.complete(credential);
        await NfcManager.instance.stopSession();
      },
    );
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
      NfcManager.instance.stopSession();
    });
    final result = await completer.future;
    timeoutTimer.cancel();
    return result;
  }

  @override
  Future<bool> writeCredentialTag(
    WifiCredential wifi, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<bool>();
    Timer? timeoutTimer;
    await NfcManager.instance.startSession(
      pollingOptions: const <NfcPollingOption>{
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (tag) async {
        final ok = await _writeNdefMessage(tag, _credentialMessage(wifi));
        if (!completer.isCompleted) completer.complete(ok);
        await NfcManager.instance.stopSession();
      },
    );
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
      NfcManager.instance.stopSession();
    });
    final result = await completer.future;
    timeoutTimer.cancel();
    return result;
  }

  static Future<NdefMessage?> _readNdefMessage(NfcTag tag) async {
    final android = NdefAndroid.from(tag);
    if (android != null) return android.getNdefMessage();
    final ios = NdefIos.from(tag);
    if (ios != null) return ios.readNdef();
    return null;
  }

  static Future<bool> _writeNdefMessage(NfcTag tag, NdefMessage message) async {
    try {
      final android = NdefAndroid.from(tag);
      if (android != null) {
        await android.writeNdefMessage(message);
        return true;
      }
      final ios = NdefIos.from(tag);
      if (ios != null) {
        await ios.writeNdef(message);
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static NdefMessage _credentialMessage(WifiCredential wifi) {
    return NdefMessage(
      records: <NdefRecord>[
        NdefRecord(
          typeNameFormat: TypeNameFormat.wellKnown,
          type: Uint8List.fromList(utf8.encode('T')),
          identifier: Uint8List(0),
          payload: _textPayload(jsonEncode(wifi.toJson())),
        ),
      ],
    );
  }

  static WifiCredential? _parseCredential(NdefMessage message) {
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.wellKnown) continue;
      final type = utf8.decode(record.type);
      if (type != 'T') continue;
      final text = _decodeTextPayload(record.payload);
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) continue;
        return WifiCredential(
          ssid: decoded['ssid'] as String? ?? '',
          password: decoded['password'] as String? ?? '',
          bssid: decoded['bssid'] as String?,
          security: WifiSecurity.values.firstWhere(
            (s) => s.name == decoded['security'],
            orElse: () => WifiSecurity.wpa2,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Builds an NDEF text-record payload (status byte + language + text).
  /// 构造 NDEF 文本记录载荷（状态字节 + 语言 + 文本）。
  static Uint8List _textPayload(String text) {
    final language = utf8.encode('en');
    final body = BytesBuilder()
      ..addByte(0x02) // UTF-8, language length 3 bits
      ..add(language)
      ..add(utf8.encode(text));
    return body.toBytes();
  }

  static String _decodeTextPayload(Uint8List payload) {
    if (payload.isEmpty) return '';
    final status = payload[0];
    final languageLength = status & 0x3F;
    final isUtf8 = (status & 0x80) == 0;
    final textBytes = payload.sublist(1 + languageLength);
    return isUtf8 ? utf8.decode(textBytes) : latin1.decode(textBytes);
  }
}

/// SoftAP provisioning channel (Android full support; iOS can only guide the
/// user to switch Wi-Fi manually). / SoftAP 配网通道（Android 完整支持；
/// iOS 只能引导用户手动切换 Wi-Fi）。
class WifiIotSoftApChannel implements SoftApProvisioningChannel {
  const WifiIotSoftApChannel({
    this.deviceHost = '192.168.4.1',
    this.path = '/provision',
    this.timeout = const Duration(seconds: 15),
  });

  /// Device SoftAP HTTP endpoint host. / 设备 SoftAP HTTP 端点主机。
  final String deviceHost;

  /// Provisioning path. / 配网路径。
  final String path;

  /// HTTP timeout. / HTTP 超时。
  final Duration timeout;

  @override
  Future<bool> provision({
    required String deviceApSsid,
    required WifiCredential wifi,
  }) async {
    final connected = await WiFiForIoTPlugin.connect(
      deviceApSsid,
      security: NetworkSecurity.NONE,
      joinOnce: true,
      withInternet: false,
      timeoutInSeconds: timeout.inSeconds,
    );
    if (!connected) return false;
    final response = await http
        .post(
          Uri.parse('http://$deviceHost$path'),
          headers: <String, String>{'content-type': 'application/json'},
          body: jsonEncode(wifi.toJson()),
        )
        .timeout(timeout);
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
