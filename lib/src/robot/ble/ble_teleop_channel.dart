import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../teleop_channel.dart';
import 'ble_device.dart';
import 'ble_link.dart';
import 'flutter_blue_plus_link.dart';

/// Teleop control channel over a persistent BLE GATT connection.
/// 基于持久 BLE GATT 连接的控制通道。
///
/// Implements [TeleopChannel] so it drops straight into [RobotController]
/// (and [DualTeleopChannel] as a resilient secondary). Commands and telemetry
/// reuse the exact JSON envelopes of the other channels, so the device firmware
/// only needs to speak one command dialect. / 实现 [TeleopChannel]，可直接接入
/// [RobotController]（或作为 [DualTeleopChannel] 的韧性备线）。指令与遥测复用
/// 其它通道的 JSON 封包，固件只需实现同一套指令方言。
class BleTeleopChannel implements TeleopChannel {
  BleTeleopChannel({required BleLink link}) : _link = link;

  /// Convenience factory wiring the default `flutter_blue_plus` transport.
  /// 便捷工厂：直接接上默认的 `flutter_blue_plus` 传输。
  factory BleTeleopChannel.forDevice(
    BleDevice device, {
    String serviceUuid = kTeleopServiceUuid,
    String commandCharUuid = kTeleopCommandCharUuid,
    String telemetryCharUuid = kTeleopTelemetryCharUuid,
    License license = License.nonprofit,
    int requestedMtu = 256,
    bool autoReconnect = true,
    int maxReconnectAttempts = 10,
  }) => BleTeleopChannel(
    link: FlutterBluePlusBleLink(
      device,
      serviceUuid: serviceUuid,
      commandCharUuid: commandCharUuid,
      telemetryCharUuid: telemetryCharUuid,
      license: license,
      requestedMtu: requestedMtu,
      autoReconnect: autoReconnect,
      maxReconnectAttempts: maxReconnectAttempts,
    ),
  );

  final BleLink _link;
  final StreamController<RobotTelemetry> _telemetryCtrl =
      StreamController<RobotTelemetry>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _telemetrySub;
  StreamSubscription<bool>? _stateSub;
  bool _started = false;

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    _telemetrySub = _link.telemetry.listen((map) {
      final telemetry = RobotTelemetry.tryFromJson(map);
      if (telemetry != null) _telemetryCtrl.add(telemetry);
    });
    _stateSub = _link.connectionState.listen((connected) {
      // Mirror the MQTT channel: surface a connected / disconnected telemetry
      // frame so downstream consumers (RobotController, the example link tile)
      // reflect the link state even when the device sends no telemetry of its
      // own. / 与 MQTT 通道一致：广播"在线 / 离线"遥测帧，即使设备自身不下发
      // 遥测，下游（RobotController、示例链路标签）也能正确反映链路状态。
      _telemetryCtrl.add(RobotTelemetry(online: connected));
    });
  }

  @override
  Future<void> connect(String deviceId) async {
    _ensureStarted();
    await _link.connect();
  }

  @override
  Future<void> disconnect() async {
    await _link.disconnect();
  }

  @override
  Future<bool> sendVelocity(Velocity velocity) => _link.writeCommand(
    <String, dynamic>{'type': 'velocity', ...velocity.toJson()},
  );

  @override
  Future<bool> sendPtz(PtzCommand command) =>
      _link.writeCommand(<String, dynamic>{'type': 'ptz', ...command.toJson()});

  @override
  Future<bool> sendStop() =>
      _link.writeCommand(<String, dynamic>{'type': 'stop'});

  @override
  Stream<RobotTelemetry> get telemetry => _telemetryCtrl.stream;

  @override
  bool get isConnected => _link.isConnected;

  /// Releases internal stream subscriptions. Call it when the owning
  /// [RobotController] is disposed; not part of [TeleopChannel] because the
  /// controller outlives individual connect/disconnect cycles (BLE auto-reconnect
  /// keeps the channel alive across drops).
  /// 释放内部订阅。在持有的 [RobotController] 释放时调用；它不在 [TeleopChannel]
  /// 内，因为控制器比单次连接更长寿（BLE 自动重连使通道在抖动中保持存活）。
  Future<void> dispose() async {
    await _telemetrySub?.cancel();
    await _stateSub?.cancel();
    await _telemetryCtrl.close();
  }
}
