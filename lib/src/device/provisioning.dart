import 'dart:async';

import 'package:logging/logging.dart';

import '../core/rtc_events.dart';

/// Provisioning method (unified abstraction, auto-degrades).
/// 配网方式（统一抽象，自动降级）。
enum ProvisionMethod {
  /// Pick by device capability and platform (strategy chain). / 按设备能力与平台自动选路（策略链）。
  auto,

  /// BLE provisioning (ESP32 protocomm, best cross-platform UX). / BLE 配网（ESP32 protocomm，跨平台体验最佳）。
  ble,

  /// Wi-Fi Easy Connect / DPP (Android 10+ system capability). / Wi-Fi Easy Connect / DPP（Android 10+ 系统能力）。
  dpp,

  /// NFC tap-to-provision (NDEF tags). / NFC 碰一碰配网（NDEF 标签）。
  nfc,

  /// SoftAP (device opens an AP; app posts credentials over HTTP). / SoftAP（设备开热点；App 经 HTTP 下发凭据）。
  softAp,

  /// SmartConfig / ESP-Touch (last resort, compatibility issues). / SmartConfig / ESP-Touch（最后兜底，兼容性差）。
  smartConfig,
}

/// Provisioning state. / 配网状态。
enum ProvisioningState {
  /// Idle. / 空闲。
  idle,

  /// Scanning for devices. / 正在扫描设备。
  scanning,

  /// Connecting to the device (BLE / SoftAP). / 正在连接设备（BLE / SoftAP）。
  connecting,

  /// Sending credentials. / 正在下发凭据。
  sendingCredentials,

  /// Verifying the device joined the network. / 正在验证设备入网。
  verifying,

  /// Success. / 成功。
  success,

  /// Failed (see the reason). / 失败（见原因）。
  failed,
}

/// Failure classification. / 失败原因分类。
enum ProvisionFailureReason {
  /// No failure. / 无失败。
  none,

  /// Wrong Wi-Fi password. / Wi-Fi 密码错误。
  wrongPassword,

  /// Weak signal / AP not found. / 信号弱 / 找不到 AP。
  weakSignal,

  /// Timeout. / 超时。
  timeout,

  /// Protocol mismatch (device firmware). / 协议不匹配（设备固件）。
  protocolMismatch,

  /// Permission denied. / 权限被拒。
  permissionDenied,

  /// Platform does not support the method. / 平台不支持该方式。
  unsupportedPlatform,

  /// Cancelled by the app. / App 取消。
  cancelled,

  /// Unknown. / 未知。
  unknown,
}

/// Wi-Fi security type. / Wi-Fi 加密类型。
enum WifiSecurity {
  /// Open network. / 开放网络。
  none,

  /// WEP. / WEP。
  wep,

  /// WPA. / WPA。
  wpa,

  /// WPA2. / WPA2。
  wpa2,

  /// WPA3. / WPA3。
  wpa3,
}

/// Wi-Fi credential. / Wi-Fi 凭据。
class WifiCredential {
  const WifiCredential({
    required this.ssid,
    this.password = '',
    this.bssid,
    this.security = WifiSecurity.wpa2,
  });

  final String ssid;
  final String password;
  final String? bssid;
  final WifiSecurity security;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ssid': ssid,
    'password': password,
    if (bssid != null) 'bssid': bssid,
    'security': security.name,
  };
}

/// A discovered provisionable device. / 发现的可配网设备。
class ProvisionDevice {
  const ProvisionDevice({
    required this.id,
    required this.name,
    this.capabilities = const <ProvisionMethod>{},
    this.rssi,
    this.platformDevice,
  });

  /// Stable device id (BLE address, SoftAP SSID, …). / 稳定设备 id（BLE 地址、SoftAP SSID 等）。
  final String id;

  /// Display name. / 显示名。
  final String name;

  /// Methods this device supports. / 该设备支持的方式。
  final Set<ProvisionMethod> capabilities;

  /// Signal strength when known. / 信号强度（如已知）。
  final int? rssi;

  /// Underlying platform object (e.g. `BluetoothDevice`). / 底层平台对象（如 `BluetoothDevice`）。
  final Object? platformDevice;

  /// Whether the device supports [method]. / 设备是否支持 [method]。
  bool supports(ProvisionMethod method) => capabilities.contains(method);
}

/// Provisioning status snapshot. / 配网状态快照。
class ProvisioningStatus {
  const ProvisioningStatus({
    this.state = ProvisioningState.idle,
    this.method = ProvisionMethod.auto,
    this.reason = ProvisionFailureReason.none,
    this.deviceId,
    this.message,
  });

  final ProvisioningState state;
  final ProvisionMethod method;
  final ProvisionFailureReason reason;
  final String? deviceId;
  final String? message;

  ProvisioningStatus copyWith({
    ProvisioningState? state,
    ProvisionMethod? method,
    ProvisionFailureReason? reason,
    String? deviceId,
    String? message,
  }) {
    return ProvisioningStatus(
      state: state ?? this.state,
      method: method ?? this.method,
      reason: reason ?? this.reason,
      deviceId: deviceId ?? this.deviceId,
      message: message ?? this.message,
    );
  }
}

/// BLE provisioning channel (device side). / BLE 配网通道（设备侧）。
abstract class BleProvisioningChannel {
  /// Scans for BLE provisioning devices. / 扫描 BLE 配网设备。
  Future<List<ProvisionDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  });

  /// Provisions [device] over BLE. / 通过 BLE 为 [device] 配网。
  Future<bool> provision(ProvisionDevice device, WifiCredential wifi);
}

/// DPP provisioning channel (Android-only, platform channel). / DPP 配网通道（仅 Android，平台通道）。
abstract class DppProvisioningChannel {
  /// Starts the system DPP configurator with the scanned QR content. / 用扫描到的二维码内容启动系统 DPP 配置器。
  Future<bool> provision({required String qrContent});
}

/// NFC provisioning channel. / NFC 配网通道。
abstract class NfcProvisioningChannel {
  /// Waits for an NFC tag carrying credentials and returns them. / 等待携带凭据的 NFC 标签并返回凭据。
  Future<WifiCredential?> readCredentialTag();

  /// Writes credentials to a tag (factory / showroom setup). / 把凭据写入标签（产线 / 展厅布设）。
  Future<bool> writeCredentialTag(WifiCredential wifi);
}

/// SoftAP provisioning channel. / SoftAP 配网通道。
abstract class SoftApProvisioningChannel {
  /// Connects to the device AP and posts credentials. / 连接设备热点并下发凭据。
  Future<bool> provision({
    required String deviceApSsid,
    required WifiCredential wifi,
  });
}

/// SmartConfig channel (vendor SDK expected). / SmartConfig 通道（需厂商 SDK）。
abstract class SmartConfigChannel {
  /// Runs the vendor SmartConfig flow. / 执行厂商 SmartConfig 流程。
  Future<bool> provision(WifiCredential wifi);
}

/// Unified device provisioning with a degrading strategy chain.
/// 统一设备配网入口，策略链自动降级。
///
/// Chain order (see the connection matrix): BLE → DPP (Android) → NFC →
/// SoftAP → SmartConfig. Business code never picks a channel itself.
/// 策略链顺序（见连接矩阵）：BLE → DPP（Android）→ NFC → SoftAP → SmartConfig。
/// 业务层永远不自己选通道。
class DeviceProvisioning {
  DeviceProvisioning({
    BleProvisioningChannel? ble,
    DppProvisioningChannel? dpp,
    NfcProvisioningChannel? nfc,
    SoftApProvisioningChannel? softAp,
    SmartConfigChannel? smartConfig,
    Logger? logger,
  }) : _ble = ble,
       _dpp = dpp,
       _nfc = nfc,
       _softAp = softAp,
       _smartConfig = smartConfig,
       _logger = logger ?? Logger('DeviceProvisioning');

  final BleProvisioningChannel? _ble;
  final DppProvisioningChannel? _dpp;
  final NfcProvisioningChannel? _nfc;
  final SoftApProvisioningChannel? _softAp;
  final SmartConfigChannel? _smartConfig;
  final Logger _logger;

  final StreamController<ProvisioningStatus> _statusCtrl =
      StreamController<ProvisioningStatus>.broadcast();
  ProvisioningStatus _status = const ProvisioningStatus();

  /// Status stream. / 状态流。
  Stream<ProvisioningStatus> get status => _statusCtrl.stream;

  /// Current status. / 当前状态。
  ProvisioningStatus get currentStatus => _status;

  /// Device events (mirrors [status] as [ProvisioningStateChanged]). / 设备事件（把 [status] 映射为 [ProvisioningStateChanged]）。
  Stream<DeviceEvent> get deviceEvents => _statusCtrl.stream.map(
    (s) => ProvisioningStateChanged(
      state: s.state,
      method: s.method,
      reason: s.reason == ProvisionFailureReason.none ? null : s.reason,
      deviceId: s.deviceId,
    ),
  );

  /// Scans for BLE provisioning devices. / 扫描 BLE 配网设备。
  Future<List<ProvisionDevice>> scanBle({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _update(
      _status.copyWith(
        state: ProvisioningState.scanning,
        method: ProvisionMethod.ble,
      ),
    );
    final channel = _ble;
    if (channel == null) {
      _fail(
        ProvisionMethod.ble,
        ProvisionFailureReason.unsupportedPlatform,
        'No BLE provisioning channel configured.',
      );
      return const <ProvisionDevice>[];
    }
    try {
      final devices = await channel.scan(timeout: timeout);
      _update(_status.copyWith(state: ProvisioningState.idle));
      return devices;
    } catch (e) {
      _fail(ProvisionMethod.ble, ProvisionFailureReason.unknown, '$e');
      return const <ProvisionDevice>[];
    }
  }

  /// Provisions [device], degrading down the strategy chain on failure.
  /// 为 [device] 配网，失败时沿策略链自动降级。
  Future<bool> provision(
    ProvisionDevice device, {
    required WifiCredential wifi,
    ProvisionMethod method = ProvisionMethod.auto,
  }) async {
    final chain = method == ProvisionMethod.auto
        ? _autoChain(device)
        : <ProvisionMethod>[method];
    if (chain.isEmpty) {
      // Nothing can provision this device here: report it instead of
      // silently returning false.
      // 此处没有任何通道可为该设备配网：明确上报，而不是静默返回 false。
      return _fail(
        method,
        ProvisionFailureReason.unsupportedPlatform,
        'No provisioning channel available for device ${device.id}.',
      );
    }
    for (final candidate in chain) {
      final ok = await _runMethod(candidate, device, wifi);
      if (ok) return true;
    }
    return false;
  }

  /// Provisions over BLE. / 通过 BLE 配网。
  Future<bool> provisionViaBle(ProvisionDevice device, WifiCredential wifi) =>
      _runMethod(ProvisionMethod.ble, device, wifi);

  /// Provisions via DPP (Android 10+). / 通过 DPP 配网（Android 10+）。
  Future<bool> provisionViaDpp({required String qrContent}) async {
    _update(
      _status.copyWith(
        state: ProvisioningState.connecting,
        method: ProvisionMethod.dpp,
      ),
    );
    final channel = _dpp;
    if (channel == null) {
      return _fail(
        ProvisionMethod.dpp,
        ProvisionFailureReason.unsupportedPlatform,
        'DPP requires Android 10+; no channel on this platform.',
      );
    }
    try {
      final ok = await channel.provision(qrContent: qrContent);
      if (!ok) {
        return _fail(
          ProvisionMethod.dpp,
          ProvisionFailureReason.timeout,
          'DPP configurator did not complete.',
        );
      }
      _update(
        _status.copyWith(
          state: ProvisioningState.success,
          method: ProvisionMethod.dpp,
          reason: ProvisionFailureReason.none,
          message: 'Device provisioned via DPP.',
        ),
      );
      return true;
    } catch (e) {
      return _fail(ProvisionMethod.dpp, ProvisionFailureReason.unknown, '$e');
    }
  }

  /// Provisions via NFC (reads a credential tag). / 通过 NFC 配网（读取凭据标签）。
  Future<bool> provisionViaNfc() async {
    _update(
      _status.copyWith(
        state: ProvisioningState.connecting,
        method: ProvisionMethod.nfc,
      ),
    );
    final channel = _nfc;
    if (channel == null) {
      return _fail(
        ProvisionMethod.nfc,
        ProvisionFailureReason.unsupportedPlatform,
        'No NFC channel configured.',
      );
    }
    try {
      final credential = await channel.readCredentialTag();
      if (credential == null) {
        return _fail(
          ProvisionMethod.nfc,
          ProvisionFailureReason.timeout,
          'No NFC credential tag presented.',
        );
      }
      _update(
        _status.copyWith(
          state: ProvisioningState.success,
          method: ProvisionMethod.nfc,
          reason: ProvisionFailureReason.none,
          message: 'Read credentials for ${credential.ssid} from NFC tag.',
        ),
      );
      return true;
    } catch (e) {
      return _fail(ProvisionMethod.nfc, ProvisionFailureReason.unknown, '$e');
    }
  }

  /// Provisions via SoftAP. / 通过 SoftAP 配网。
  Future<bool> provisionViaSoftAp({
    required String deviceApSsid,
    required WifiCredential wifi,
  }) => _runSoftAp(deviceApSsid, wifi);

  /// Provisions via SmartConfig (vendor SDK). / 通过 SmartConfig 配网（厂商 SDK）。
  Future<bool> provisionViaSmartConfig(WifiCredential wifi) async {
    _update(
      _status.copyWith(
        state: ProvisioningState.sendingCredentials,
        method: ProvisionMethod.smartConfig,
      ),
    );
    final channel = _smartConfig;
    if (channel == null) {
      return _fail(
        ProvisionMethod.smartConfig,
        ProvisionFailureReason.unsupportedPlatform,
        'SmartConfig needs a vendor SDK; integrate it as a SmartConfigChannel.',
      );
    }
    try {
      final ok = await channel.provision(wifi);
      if (!ok) {
        return _fail(
          ProvisionMethod.smartConfig,
          ProvisionFailureReason.protocolMismatch,
          'SmartConfig failed.',
        );
      }
      _update(
        _status.copyWith(
          state: ProvisioningState.success,
          method: ProvisionMethod.smartConfig,
          reason: ProvisionFailureReason.none,
        ),
      );
      return true;
    } catch (e) {
      return _fail(
        ProvisionMethod.smartConfig,
        ProvisionFailureReason.unknown,
        '$e',
      );
    }
  }

  Future<bool> _runMethod(
    ProvisionMethod method,
    ProvisionDevice device,
    WifiCredential wifi,
  ) async {
    switch (method) {
      case ProvisionMethod.ble:
        return _runBle(device, wifi);
      case ProvisionMethod.softAp:
        return _runSoftAp(device.id, wifi);
      case ProvisionMethod.dpp:
        return provisionViaDpp(qrContent: device.id);
      case ProvisionMethod.nfc:
        return provisionViaNfc();
      case ProvisionMethod.smartConfig:
        return provisionViaSmartConfig(wifi);
      case ProvisionMethod.auto:
        return false;
    }
  }

  Future<bool> _runBle(ProvisionDevice device, WifiCredential wifi) async {
    _update(
      _status.copyWith(
        state: ProvisioningState.connecting,
        method: ProvisionMethod.ble,
        deviceId: device.id,
      ),
    );
    final channel = _ble;
    if (channel == null) {
      return _fail(
        ProvisionMethod.ble,
        ProvisionFailureReason.unsupportedPlatform,
        'No BLE provisioning channel configured.',
      );
    }
    try {
      _update(_status.copyWith(state: ProvisioningState.sendingCredentials));
      final ok = await channel.provision(device, wifi);
      if (!ok) {
        return _fail(
          ProvisionMethod.ble,
          ProvisionFailureReason.protocolMismatch,
          'BLE provisioning rejected the credentials.',
        );
      }
      _update(
        _status.copyWith(
          state: ProvisioningState.success,
          reason: ProvisionFailureReason.none,
          message: 'Device ${device.id} provisioned over BLE.',
        ),
      );
      return true;
    } catch (e) {
      return _fail(ProvisionMethod.ble, ProvisionFailureReason.unknown, '$e');
    }
  }

  Future<bool> _runSoftAp(String deviceApSsid, WifiCredential wifi) async {
    _update(
      _status.copyWith(
        state: ProvisioningState.connecting,
        method: ProvisionMethod.softAp,
        deviceId: deviceApSsid,
      ),
    );
    final channel = _softAp;
    if (channel == null) {
      return _fail(
        ProvisionMethod.softAp,
        ProvisionFailureReason.unsupportedPlatform,
        'No SoftAP channel configured.',
      );
    }
    try {
      final ok = await channel.provision(
        deviceApSsid: deviceApSsid,
        wifi: wifi,
      );
      if (!ok) {
        return _fail(
          ProvisionMethod.softAp,
          ProvisionFailureReason.timeout,
          'SoftAP did not confirm the credentials.',
        );
      }
      _update(
        _status.copyWith(
          state: ProvisioningState.success,
          reason: ProvisionFailureReason.none,
          message: 'Device AP $deviceApSsid provisioned.',
        ),
      );
      return true;
    } catch (e) {
      return _fail(
        ProvisionMethod.softAp,
        ProvisionFailureReason.unknown,
        '$e',
      );
    }
  }

  List<ProvisionMethod> _autoChain(ProvisionDevice device) {
    final chain = <ProvisionMethod>[];
    if (device.supports(ProvisionMethod.ble) && _ble != null) {
      chain.add(ProvisionMethod.ble);
    }
    if (device.supports(ProvisionMethod.dpp) && _dpp != null) {
      chain.add(ProvisionMethod.dpp);
    }
    if (device.supports(ProvisionMethod.nfc) && _nfc != null) {
      chain.add(ProvisionMethod.nfc);
    }
    if (device.supports(ProvisionMethod.softAp) && _softAp != null) {
      chain.add(ProvisionMethod.softAp);
    }
    if (_smartConfig != null) {
      chain.add(ProvisionMethod.smartConfig);
    }
    return chain;
  }

  bool _fail(
    ProvisionMethod method,
    ProvisionFailureReason reason,
    String message,
  ) {
    _logger.warning('provisioning failed ($method/$reason): $message');
    _update(
      _status.copyWith(
        state: ProvisioningState.failed,
        method: method,
        reason: reason,
        message: message,
      ),
    );
    return false;
  }

  void _update(ProvisioningStatus status) {
    _status = status;
    if (!_statusCtrl.isClosed) _statusCtrl.add(status);
  }

  /// Releases resources. / 释放资源。
  Future<void> dispose() async {
    await _statusCtrl.close();
  }
}
