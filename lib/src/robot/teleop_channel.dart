import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/rtc_credentials.dart';
import '../core/rtc_events.dart';

/// Linear / angular velocity command. / 线速度 / 角速度指令。
class Velocity {
  const Velocity({this.linear = 0, this.angular = 0});

  /// Linear velocity in m/s (positive = forward). / 线速度（m/s，正为前进）。
  final double linear;

  /// Angular velocity in rad/s (positive = left turn). / 角速度（rad/s，正为左转）。
  final double angular;

  /// Whether this is a full stop. / 是否为完全停车。
  bool get isZero => linear == 0 && angular == 0;

  /// Scales the velocity (e.g. by a joystick magnitude). / 按系数缩放速度（如摇杆幅度）。
  Velocity scaled(double factor) =>
      Velocity(linear: linear * factor, angular: angular * factor);

  /// Clamps both axes to the given maxima. / 将两轴限制在给定上限内。
  Velocity clamped({required double maxLinear, required double maxAngular}) {
    return Velocity(
      linear: linear.clamp(-maxLinear, maxLinear).toDouble(),
      angular: angular.clamp(-maxAngular, maxAngular).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'linear': linear,
    'angular': angular,
  };

  @override
  String toString() => 'Velocity(linear: $linear, angular: $angular)';
}

/// Robot pose (odometry). / 机器人位姿（里程计）。
class Pose {
  const Pose({this.x = 0, this.y = 0, this.theta = 0});

  final double x;
  final double y;

  /// Heading in radians. / 朝向（弧度）。
  final double theta;

  static Pose fromJson(Map<String, dynamic> json) => Pose(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    theta: (json['theta'] as num?)?.toDouble() ?? 0,
  );
}

/// Telemetry snapshot pushed by the robot. / 机器人上报的遥测快照。
class RobotTelemetry {
  const RobotTelemetry({
    this.battery = 0,
    this.pose = const Pose(),
    this.linearSpeed = 0,
    this.angularSpeed = 0,
    this.online = false,
    this.extra = const <String, dynamic>{},
  });

  /// Battery percentage (0–100). / 电量百分比（0–100）。
  final double battery;

  /// Current pose. / 当前位姿。
  final Pose pose;

  /// Current linear speed (m/s). / 当前线速度（m/s）。
  final double linearSpeed;

  /// Current angular speed (rad/s). / 当前角速度（rad/s）。
  final double angularSpeed;

  /// Whether the robot reports itself online. / 机器人是否上报在线。
  final bool online;

  /// Vendor-specific extra fields. / 厂商自定义扩展字段。
  final Map<String, dynamic> extra;

  /// Parses a telemetry JSON payload (tolerant of missing fields).
  /// 解析遥测 JSON 载荷（容忍缺字段）。
  static RobotTelemetry? tryFromJson(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    return RobotTelemetry(
      battery: (data['battery'] as num?)?.toDouble() ?? 0,
      pose: data['pose'] is Map<String, dynamic>
          ? Pose.fromJson(data['pose'] as Map<String, dynamic>)
          : const Pose(),
      linearSpeed:
          (data['linearSpeed'] as num?)?.toDouble() ??
          (data['v'] as num?)?.toDouble() ??
          0,
      angularSpeed:
          (data['angularSpeed'] as num?)?.toDouble() ??
          (data['w'] as num?)?.toDouble() ??
          0,
      online: data['online'] as bool? ?? true,
      extra: data,
    );
  }
}

/// PTZ (pan-tilt-zoom) command. / 云台（水平 - 俯仰 - 变倍）指令。
class PtzCommand {
  const PtzCommand({required this.pan, required this.tilt, this.zoom});

  /// Pan angle in degrees. / 水平角（度）。
  final double pan;

  /// Tilt angle in degrees. / 俯仰角（度）。
  final double tilt;

  /// Optional zoom factor. / 可选变倍系数。
  final double? zoom;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'pan': pan,
    'tilt': tilt,
    if (zoom != null) 'zoom': zoom,
  };
}

/// Control channel abstraction — NEVER the media channel.
/// 控制通道抽象——绝不走媒体通道。
///
/// Commands are small, ordered, QoS 1 packets so they survive congestion that
/// would freeze video; the media channel is degraded first.
/// 指令是小包、QoS 1，能在视频卡死的拥塞下依然送达；视频通道优先被降级。
abstract class TeleopChannel {
  /// Connects the channel for [deviceId]. / 为 [deviceId] 连接通道。
  Future<void> connect(String deviceId);

  /// Disconnects the channel. / 断开通道。
  Future<void> disconnect();

  /// Sends a velocity command. / 发送速度指令。
  Future<bool> sendVelocity(Velocity velocity);

  /// Sends a PTZ command. / 发送云台指令。
  Future<bool> sendPtz(PtzCommand command);

  /// Sends an immediate stop. / 发送立即停车指令。
  Future<bool> sendStop();

  /// Telemetry stream. / 遥测流。
  Stream<RobotTelemetry> get telemetry;

  /// Whether the channel is currently connected. / 通道当前是否已连接。
  bool get isConnected;

  /// Releases the channel for good. Defaults to [disconnect] so existing
  /// implementations stay source-compatible; channels that own long-lived
  /// controllers or a transport override it. /
  /// 彻底释放通道。默认转发到 [disconnect] 以保持既有实现的源码兼容；持有长
  /// 生命周期控制器或传输层的通道应覆盖它。
  Future<void> dispose() => disconnect();
}

/// MQTT control channel (`mqtt://` / `mqtts://`). / MQTT 控制通道（`mqtt://` / `mqtts://`）。
class MqttTeleopChannel implements TeleopChannel {
  MqttTeleopChannel({
    required this.broker,
    required this.topicCmd,
    required this.topicTelemetry,
    this.credentials,
    this.keepAliveSeconds = 30,
    this.qos = MqttQos.atLeastOnce,
  });

  /// Broker URI, e.g. `mqtts://mqtt.example.com:8883`. / Broker 地址，如 `mqtts://mqtt.example.com:8883`。
  final String broker;

  /// Command topic (publish). / 指令主题（发布）。
  final String topicCmd;

  /// Telemetry topic (subscribe). / 遥测主题（订阅）。
  final String topicTelemetry;

  /// Dynamic credential factory (JWT). / 动态凭证工厂（JWT）。
  final Future<MqttCredentials?> Function()? credentials;

  final int keepAliveSeconds;
  final MqttQos qos;

  MqttServerClient? _client;
  final StreamController<RobotTelemetry> _telemetryCtrl =
      StreamController<RobotTelemetry>.broadcast();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>? _updatesSub;
  bool _connecting = false;

  @override
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Stream<RobotTelemetry> get telemetry => _telemetryCtrl.stream;

  @override
  Future<void> connect(String deviceId) async {
    if (isConnected) return;
    // Guard against concurrent connects (reconnect racing a manual call): two
    // overlapping runs used to build two clients while only the last one was
    // tracked, leaking the first socket and its subscription. /
    // 防止并发连接（重连与手动调用撞车）：重叠执行会建两个 client 而只记录最后
    // 一个，泄漏前一个 socket 及其订阅。
    if (_connecting) return;
    _connecting = true;
    try {
      // Release anything left over from a previous connection. /
      // 释放上一次连接遗留的资源。
      await _updatesSub?.cancel();
      _updatesSub = null;
      final previous = _client;
      if (previous != null) {
        previous.disconnect();
        _client = null;
      }
      final uri = Uri.parse(broker);
      final client = MqttServerClient(
        uri.host,
        'rtc-link-$deviceId-${DateTime.now().microsecondsSinceEpoch}',
      );
      client.port = uri.hasPort
          ? uri.port
          : (uri.scheme == 'mqtts' ? 8883 : 1883);
      client.secure = uri.scheme == 'mqtts';
      client.keepAlivePeriod = keepAliveSeconds;
      client.logging(on: false);
      client.onDisconnected = () {
        if (!_telemetryCtrl.isClosed) {
          _telemetryCtrl.add(const RobotTelemetry(online: false));
        }
      };
      final credentials = await this.credentials?.call();
      client.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(client.clientIdentifier)
          .startClean()
          .withWillQos(qos);
      try {
        await client.connect(credentials?.username, credentials?.password);
      } catch (e) {
        client.disconnect();
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'MQTT connect to $broker failed.',
          cause: e,
        );
      }
      // connect() reports failures via connectionStatus rather than throwing,
      // so an unchecked client would look connected while nothing flows. /
      // connect() 通过 connectionStatus 而非抛异常报告失败，因此不检查会看起来
      // 已连接却没有任何数据流动。
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        client.disconnect();
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'MQTT connect to $broker did not reach connected state.',
        );
      }
      _client = client;
      client.subscribe(topicTelemetry, qos);
      _updatesSub = client.updates?.listen(_onUpdates);
    } finally {
      _connecting = false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _client = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    if (!_telemetryCtrl.isClosed) await _telemetryCtrl.close();
  }

  @override
  Future<bool> sendVelocity(Velocity velocity) {
    return _publish(<String, dynamic>{
      'type': 'velocity',
      ...velocity.toJson(),
    });
  }

  @override
  Future<bool> sendPtz(PtzCommand command) {
    return _publish(<String, dynamic>{'type': 'ptz', ...command.toJson()});
  }

  @override
  Future<bool> sendStop() {
    return _publish(<String, dynamic>{
      'type': 'stop',
      'linear': 0,
      'angular': 0,
    });
  }

  Future<bool> _publish(Map<String, dynamic> payload) async {
    final client = _client;
    if (client == null || !isConnected) return false;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));
    client.publishMessage(topicCmd, qos, builder.payload!);
    return true;
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage?>> messages) {
    for (final message in messages) {
      if (message.topic != topicTelemetry) continue;
      final payload = message.payload;
      if (payload is! MqttPublishMessage) continue;
      final text = MqttPublishPayload.bytesToString(payload.payload.message);
      // A non-JSON payload must not escape as an unhandled async error. /
      // 非 JSON 载荷不应作为未处理的异步异常逃逸。
      try {
        final telemetry = RobotTelemetry.tryFromJson(jsonDecode(text));
        if (telemetry != null && !_telemetryCtrl.isClosed) {
          _telemetryCtrl.add(telemetry);
        }
      } catch (_) {
        // Drop malformed frames. / 丢弃畸形帧。
      }
    }
  }
}

/// Data-channel control channel (LAN, lowest latency). / 数据通道控制通道（局域网，最低延迟）。
class DataChannelTeleopChannel implements TeleopChannel {
  DataChannelTeleopChannel({required RTCDataChannel dataChannel})
    : _channel = dataChannel {
    _messageSub = dataChannel.messageStream.listen((message) {
      if (!message.isBinary) {
        // A non-JSON payload must not escape as an unhandled async error. /
        // 非 JSON 载荷不应作为未处理的异步异常逃逸。
        try {
          final telemetry = RobotTelemetry.tryFromJson(
            jsonDecode(message.text),
          );
          if (telemetry != null) _telemetryCtrl.add(telemetry);
        } catch (_) {
          // Drop malformed frames. / 丢弃畸形帧。
        }
      }
    });
    _stateSub = dataChannel.stateChangeStream.listen((state) {
      _connected = state == RTCDataChannelState.RTCDataChannelOpen;
    });
  }

  final RTCDataChannel _channel;
  final StreamController<RobotTelemetry> _telemetryCtrl =
      StreamController<RobotTelemetry>.broadcast();
  late final StreamSubscription<RTCDataChannelMessage> _messageSub;
  late final StreamSubscription<RTCDataChannelState> _stateSub;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<RobotTelemetry> get telemetry => _telemetryCtrl.stream;

  @override
  Future<void> connect(String deviceId) async {
    // The data channel is created and opened by the media session.
    // 数据通道由媒体会话创建并打开。
    _connected = _channel.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  @override
  Future<void> disconnect() async {
    await _messageSub.cancel();
    await _stateSub.cancel();
    await _telemetryCtrl.close();
  }

  @override
  Future<void> dispose() async {
    // Idempotent: disconnect() may already have run. /
    // 幂等：disconnect() 可能已执行过。
    await _messageSub.cancel();
    await _stateSub.cancel();
    if (!_telemetryCtrl.isClosed) await _telemetryCtrl.close();
  }

  @override
  Future<bool> sendVelocity(Velocity velocity) => _send(velocity.toJson());

  @override
  Future<bool> sendPtz(PtzCommand command) => _send(command.toJson());

  @override
  Future<bool> sendStop() => _send(<String, dynamic>{'type': 'stop'});

  Future<bool> _send(Map<String, dynamic> payload) async {
    if (!isConnected) return false;
    await _channel.send(RTCDataChannelMessage(jsonEncode(payload)));
    return true;
  }
}

/// Dual control channel: sends on both paths, degrades gracefully.
/// 双控制通道：双路发送，优雅降级。
class DualTeleopChannel implements TeleopChannel {
  DualTeleopChannel({
    required TeleopChannel primary,
    required TeleopChannel secondary,
  }) : _primary = primary,
       _secondary = secondary;

  final TeleopChannel _primary;
  final TeleopChannel _secondary;
  final StreamController<RobotTelemetry> _telemetryCtrl =
      StreamController<RobotTelemetry>.broadcast();
  // Nullable, not `late final`: disconnect() may run before connect() ever
  // succeeded (or at all), and `late final` throws LateInitializationError
  // there. Also, `late final` can only be assigned once, so a second connect()
  // crashed. / 用可空而非 `late final`：disconnect() 可能在 connect() 从未成功
  // （或从未调用）时执行，`late final` 会抛 LateInitializationError；且
  // `late final` 只能赋值一次，第二次 connect() 会崩溃。
  StreamSubscription<RobotTelemetry>? _primarySub;
  StreamSubscription<RobotTelemetry>? _secondarySub;

  @override
  bool get isConnected => _primary.isConnected || _secondary.isConnected;

  @override
  Stream<RobotTelemetry> get telemetry => _telemetryCtrl.stream;

  @override
  Future<void> connect(String deviceId) async {
    await _primary.connect(deviceId);
    await _secondary.connect(deviceId);
    // Cancel previous listeners first: a reconnect must not double-deliver
    // telemetry. / 先取消旧监听：重连不能重复投递遥测。
    await _primarySub?.cancel();
    await _secondarySub?.cancel();
    _primarySub = _primary.telemetry.listen(_telemetryCtrl.add);
    _secondarySub = _secondary.telemetry.listen(_telemetryCtrl.add);
  }

  @override
  Future<void> disconnect() async {
    await _primarySub?.cancel();
    await _secondarySub?.cancel();
    _primarySub = null;
    _secondarySub = null;
    await _primary.disconnect();
    await _secondary.disconnect();
    // Do NOT close _telemetryCtrl here: this channel can be connect()ed again,
    // and a closed controller throws on the next telemetry frame. Call
    // dispose() when the channel is discarded for good. /
    // 此处不要关闭 _telemetryCtrl：本通道可以再次 connect()，而关闭的控制器会在
    // 下一条遥测帧时抛异常。彻底丢弃通道时请调用 dispose()。
  }

  /// Releases this channel for good, closing the telemetry controller.
  /// 彻底释放本通道，关闭遥测控制器。
  @override
  Future<void> dispose() async {
    await disconnect();
    if (!_telemetryCtrl.isClosed) await _telemetryCtrl.close();
  }

  @override
  Future<bool> sendVelocity(Velocity velocity) async {
    final a = await _primary.sendVelocity(velocity);
    final b = await _secondary.sendVelocity(velocity);
    return a || b;
  }

  @override
  Future<bool> sendPtz(PtzCommand command) async {
    final a = await _primary.sendPtz(command);
    final b = await _secondary.sendPtz(command);
    return a || b;
  }

  @override
  Future<bool> sendStop() async {
    final a = await _primary.sendStop();
    final b = await _secondary.sendStop();
    return a || b;
  }
}
