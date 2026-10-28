/// A discovered BLE device. / 已发现的 BLE 设备。
///
/// Kept free of `flutter_blue_plus` types so the public API never leaks the
/// transport: a link resolves the concrete platform device from [id] (the BLE
/// remote id) internally.
/// 不暴露 `flutter_blue_plus` 类型，使公开 API 不泄漏传输层：link 内部会用
/// [id]（BLE 远端 id）还原出具体的平台设备。
///
/// This lives in the protocol-agnostic `ble/` module because both the generic
/// GATT client and the robot control link build on it.
/// 放在与协议无关的 `ble/` 模块中，因为通用 GATT 客户端与机器人控制链路都以
/// 它为基础。
class BleDevice {
  const BleDevice({required this.id, required this.name, this.rssi = 0});

  /// BLE remote id (e.g. MAC address on Android, UUID on iOS).
  /// BLE 远端 id（Android 上为 MAC，iOS 上为 UUID）。
  final String id;

  /// Advertised name (may be empty until a connection is made).
  /// 广播名（连接前可能为空）。
  final String name;

  /// Received signal strength (dBm). / 信号强度（dBm）。
  final int rssi;

  /// A display label. / 展示用名称。
  String get label => name.isNotEmpty ? name : id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BleDevice(id: $id, name: $name, rssi: $rssi)';
}
