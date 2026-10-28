import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

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

/// Reads and writes the credential payload on an NFC tag.
/// 读写 NFC 标签上的凭据载荷。
///
/// The plugin deliberately ships no NFC stack: hardware access is an app
/// decision (and an app-store privacy declaration), so the app injects an
/// implementation — for example one built on `nfc_manager` — and the plugin
/// only handles the credential payload on top of it.
/// 插件刻意不自带 NFC 技术栈：硬件访问应由应用决定（且涉及应用商店隐私声明），
/// 因此由应用注入一个实现（例如基于 `nfc_manager` 的实现），插件只在其之上处理
/// 凭据载荷。
abstract class NfcTagBackend {
  /// Reads the text stored on the next discovered tag; null on timeout or when
  /// no readable text is found. / 读取下一个被发现的标签上存储的文本；超时或未
  /// 找到可读文本时返回 null。
  Future<String?> readText({Duration timeout = const Duration(seconds: 30)});

  /// Writes [text] to the next discovered tag. / 将 [text] 写入下一个被发现的标签。
  Future<bool> writeText(
    String text, {
    Duration timeout = const Duration(seconds: 30),
  });
}

/// NFC provisioning channel (credential tags). / NFC 配网通道（凭据标签）。
///
/// Knows nothing about the NFC stack: it encodes [WifiCredential] as JSON and
/// delegates every tag operation to [backend].
/// 不了解 NFC 技术栈：它把 [WifiCredential] 编码为 JSON，所有标签操作都交给
/// [backend]。
class NfcProvisioningChannelImpl implements NfcProvisioningChannel {
  const NfcProvisioningChannelImpl({required this.backend});

  /// Injected NFC tag I/O. / 注入的 NFC 标签读写实现。
  final NfcTagBackend backend;

  @override
  Future<WifiCredential?> readCredentialTag({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final text = await backend.readText(timeout: timeout);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
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
      return null;
    }
  }

  @override
  Future<bool> writeCredentialTag(
    WifiCredential wifi, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return backend.writeText(jsonEncode(wifi.toJson()), timeout: timeout);
  }
}

/// Joins the phone to a device's open SoftAP network. / 让手机连上设备的开放 SoftAP 网络。
///
/// Injected for the same reason as [NfcTagBackend]: joining Wi-Fi networks is a
/// platform capability the app owns, not something a media plugin should force
/// on every consumer.
/// 注入的原因同 [NfcTagBackend]：连接 Wi-Fi 是应用拥有的平台能力，不该由媒体
/// 插件强加给每一个使用者。
abstract class WifiNetworkConnector {
  /// Joins the open (no-password) network [ssid]. / 加入开放的（无密码）网络 [ssid]。
  Future<bool> connectToOpenNetwork(
    String ssid, {
    Duration timeout = const Duration(seconds: 15),
  });
}

/// SoftAP provisioning channel (Android full support; iOS can only guide the
/// user to switch Wi-Fi manually). / SoftAP 配网通道（Android 完整支持；
/// iOS 只能引导用户手动切换 Wi-Fi）。
///
/// Joins the device AP through [connector], then POSTs the credentials.
/// 先经 [connector] 连上设备 AP，再 POST 凭据。
class SoftApProvisioningChannelImpl implements SoftApProvisioningChannel {
  const SoftApProvisioningChannelImpl({
    required this.connector,
    this.deviceHost = '192.168.4.1',
    this.path = '/provision',
    this.timeout = const Duration(seconds: 15),
  });

  /// Injected Wi-Fi joiner. / 注入的 Wi-Fi 连接器。
  final WifiNetworkConnector connector;

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
    final connected = await connector.connectToOpenNetwork(
      deviceApSsid,
      timeout: timeout,
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
