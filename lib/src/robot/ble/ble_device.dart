/// A discovered BLE device for the teleop control channel.
/// 用于遥测控制通道的已发现 BLE 设备。
///
/// Unlike [ProvisionDevice], this keeps the public API free of
/// `flutter_blue_plus` types; the link resolves the concrete
/// [BluetoothDevice] from [id] (the BLE remote id) internally.
/// 与 [ProvisionDevice] 不同，这里不向公开 API 暴露 `flutter_blue_plus`
/// 类型；link 内部会用 [id]（BLE 远端 id）还原出具体的 `BluetoothDevice`。
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
