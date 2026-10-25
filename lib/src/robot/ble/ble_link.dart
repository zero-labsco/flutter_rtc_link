import 'dart:async';

/// Transport contract for the BLE teleop channel.
/// BLE 遥测控制通道的传输契约。
///
/// Implementations move JSON command / telemetry maps over GATT; the
/// [BleTeleopChannel] turns them into the [TeleopChannel] envelope. A fake
/// implementation backs the unit tests so the transport never needs a real
/// device. / 实现层在 GATT 上搬运 JSON 指令 / 遥测；[BleTeleopChannel] 再把它
/// 们转成 [TeleopChannel] 封包。单测用假实现支撑，无需真实设备。
abstract class BleLink {
  /// Opens the connection (scan + connect + discover + subscribe).
  /// 建立连接（扫描 + 连接 + 发现服务 + 订阅）。
  Future<void> connect();

  /// Closes the connection and stops any auto-reconnect.
  /// 关闭连接并停止自动重连。
  Future<void> disconnect();

  /// Writes a command payload to the device. Returns false if not connected.
  /// 向设备写入指令载荷；未连接时返回 false。
  Future<bool> writeCommand(Map<String, dynamic> payload);

  /// Telemetry maps pushed by the device (JSON decoded).
  /// 设备推送的遥测（已解码的 JSON）。
  Stream<Map<String, dynamic>> get telemetry;

  /// Connection state stream (true = connected). / 连接状态流（true = 已连接）。
  Stream<bool> get connectionState;

  /// Whether the link is currently connected. / 当前是否已连接。
  bool get isConnected;
}
