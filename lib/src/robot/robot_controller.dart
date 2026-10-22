import 'dart:async';

import '../core/rtc_events.dart';
import '../publishers/local_publisher.dart';
import '../resilience/control_link.dart';
import '../resilience/link_events.dart';
import '../resilience/pause_resume_gate.dart';
import 'teleop_channel.dart';

/// Robot teleoperation controller (control channel only).
/// 机器人遥控控制器（仅控制通道）。
///
/// Latency budget: command end-to-end < 200 ms (LAN < 80 ms). The watchdog is
/// a hard safety requirement: if no command arrives within
/// [watchdogTimeout], the robot is stopped immediately (also on link loss).
/// 时延预算：指令端到端 < 200ms（局域网 < 80ms）。看门狗是硬性安全要求：
/// [watchdogTimeout] 内未收到指令即立即停车（断链同样处理）。
class RobotController {
  RobotController({
    required TeleopChannel channel,
    this.watchdogTimeout = const Duration(milliseconds: 500),
    this.commandInterval = const Duration(milliseconds: 100),
    this.maxLinear = 1.0,
    this.maxAngular = 1.5,
    PauseResumeGate? gate,
    CommandRateLimiter? rateLimiter,
  }) : _channel = channel,
       _gate = gate,
       _rateLimiter = rateLimiter;

  final TeleopChannel _channel;

  /// Gate that stamps and validates every command. When null, the controller
  /// keeps its legacy (unguarded) behaviour.
  /// 为每条指令盖章并校验的门。为 null 时控制器沿用旧的无管控行为。
  final PauseResumeGate? _gate;

  /// Optional joystick throttle (latest-wins instead of flooding the link).
  /// 可选的摇杆限流器（最新者胜，而不是把链路灌满）。
  final CommandRateLimiter? _rateLimiter;

  /// Watchdog timeout: stop when no command arrives in time. / 看门狗超时：超时未收到指令即停车。
  final Duration watchdogTimeout;

  /// Keepalive interval for the current velocity. / 当前速度的保活间隔。
  final Duration commandInterval;

  /// Max linear speed (m/s). / 最大线速度（m/s）。
  final double maxLinear;

  /// Max angular speed (rad/s). / 最大角速度（rad/s）。
  final double maxAngular;

  final StreamController<DeviceEvent> _eventsCtrl =
      StreamController<DeviceEvent>.broadcast();
  Timer? _watchdogTimer;
  Timer? _repeatTimer;
  Velocity _currentVelocity = const Velocity();
  String? _deviceId;
  DateTime? _lastCommandAt;
  bool _watchdogTripped = false;
  bool _disposed = false;
  int _commandEpoch = 0;

  /// Device id once connected. / 连接后的设备 id。
  String? get deviceId => _deviceId;

  /// Last commanded velocity. / 最近下达的速度。
  Velocity get currentVelocity => _currentVelocity;

  /// Whether the watchdog is armed (a velocity command is active). / 看门狗是否已布防（有活跃速度指令）。
  bool get isWatchdogArmed => _watchdogTimer?.isActive ?? false;

  /// Whether the watchdog has tripped since the last command. / 自最近一条指令以来看门狗是否已触发过。
  bool get hasWatchdogTripped => _watchdogTripped;

  /// Whether commands are suspended by the pause/resume gate.
  /// 指令是否被暂停 / 恢复门挂起。
  bool get isPaused => _gate?.isPaused ?? false;

  /// Epoch that commands must currently carry. / 当前指令必须携带的 epoch。
  int get commandEpoch => _gate?.epoch ?? 0;

  /// Gate guarding every command (configurable). / 守卫所有指令的门（可配置）。
  PauseResumeGate? get gate => _gate;

  /// Telemetry stream from the control channel. / 来自控制通道的遥测流。
  Stream<RobotTelemetry> get telemetry => _channel.telemetry;

  /// Device events (watchdog trips, …). / 设备事件（看门狗触发等）。
  Stream<DeviceEvent> get events => _eventsCtrl.stream;

  /// Connects the control channel for [deviceId]. / 为 [deviceId] 连接控制通道。
  Future<void> connect({required String deviceId}) async {
    _deviceId = deviceId;
    await _channel.connect(deviceId);
  }

  /// Commands a velocity (joystick input). / 下达速度指令（摇杆输入）。
  ///
  /// Arms the watchdog and starts the keepalive; pass [Velocity] zero (or
  /// call [stop]) to release the joystick.
  /// 布防看门狗并启动保活；传入零 [Velocity]（或调用 [stop]）表示松开摇杆。
  Future<void> move(Velocity velocity) async {
    final clamped = velocity.clamped(
      maxLinear: maxLinear,
      maxAngular: maxAngular,
    );
    final epoch = _gate?.stamp() ?? 0;
    _currentVelocity = clamped;
    if (!_accepts(epoch)) {
      // Suspended (background / link lost): the command is dropped, never
      // buffered for a later replay.
      // 已暂停（后台 / 断链）：指令被丢弃，绝不缓存到之后补发。
      _dropStale(epoch);
      return;
    }
    final limiter = _rateLimiter;
    if (limiter != null && !limiter.allow()) {
      // Latest wins: the keepalive loop will send the newest velocity.
      // 最新者胜：保活循环会发出最新的速度。
      _lastCommandAt = DateTime.now();
      _armWatchdog();
      return;
    }
    _watchdogTripped = false;
    final sent = await _channel.sendVelocity(clamped);
    if (!sent) {
      // A command the channel refuses is a lost-control event, not a
      // "try again later" one: stop immediately.
      // 通道拒绝的指令意味着失去控制，而不是"稍后重试"：立即停车。
      _onWatchdog();
      return;
    }
    if (!_accepts(epoch)) {
      // The pause happened while the command was in flight: the robot must
      // not keep acting on it, and the watchdog must disarm.
      // 指令在飞行途中发生了暂停：机器人不能继续按它动作，看门狗也要撤防。
      _disarmWatchdog();
      _currentVelocity = const Velocity();
      _dropStale(epoch);
      return;
    }
    _commandEpoch = epoch;
    _lastCommandAt = DateTime.now();
    _armWatchdog();
    _repeatTimer ??= Timer.periodic(
      commandInterval,
      (_) => unawaited(_keepalive()),
    );
  }

  /// Commands the PTZ head. / 下达云台指令。
  Future<void> setPtz({
    required double pan,
    required double tilt,
    double? zoom,
  }) async {
    final epoch = _gate?.stamp() ?? 0;
    if (!_accepts(epoch)) {
      _dropStale(epoch);
      return;
    }
    _lastCommandAt = DateTime.now();
    await _channel.sendPtz(PtzCommand(pan: pan, tilt: tilt, zoom: zoom));
  }

  /// Stops the robot and disarms the watchdog. / 停车并撤防看门狗。
  Future<void> stop() async {
    _currentVelocity = const Velocity();
    _disarmWatchdog();
    await _channel.sendStop();
  }

  /// Enables voice intercom by making sure the operator's microphone track is
  /// published; the robot subscribes and plays it back.
  /// 通过确保操作者麦克风轨道已发布来开启语音对讲；机器人端订阅并播放。
  Future<void> enableVoiceIntercom(LocalPublisher publisher) async {
    if (!publisher.isMicActive) {
      await publisher.startMic();
    }
    if (publisher.status.value.micMuted) {
      await publisher.setMicMuted(false);
    }
  }

  /// Suspends teleoperation: stops the robot at once and invalidates every
  /// command issued before now. / 暂停遥控：立即停车，并让此前所有指令失效。
  ///
  /// Commands produced before the pause are dropped, never replayed, so the
  /// robot can never resume moving from a joystick position the operator
  /// forgot about while the app was in the background.
  /// 暂停前产生的指令会被丢弃而非补发，因此机器人绝不会因为在后台期间被遗忘的
  /// 摇杆位置而重新动起来。
  Future<void> pause(PauseReason reason) async {
    final gate = _gate;
    _currentVelocity = const Velocity();
    _disarmWatchdog();
    // Safety first: never leave the machine driving during a suspension.
    // 安全优先：暂停期间绝不能让机器继续运行。
    await _channel.sendStop();
    if (gate == null) return;
    gate.pause(reason);
    _emit(
      RobotControlPaused(
        deviceId: _deviceId ?? '',
        reason: reason.name,
        epoch: gate.epoch,
      ),
    );
  }

  /// Issues the resume ticket the operator must confirm.
  /// 签发出操作者必须确认的恢复票据。
  ResumeTicket? requestResume() => _gate?.requestResume();

  /// Confirms a resume; returns false for unknown, expired or foreign tickets.
  /// 确认恢复；票据未知、过期或不匹配时返回 false。
  Future<bool> confirmResume([ResumeTicket? ticket]) async {
    final gate = _gate;
    if (gate == null) return true;
    final target = ticket ?? gate.pendingTicket;
    if (target == null) return false;
    final ok = gate.confirmResume(target);
    if (ok) {
      _emit(RobotControlResumed(deviceId: _deviceId ?? '', epoch: gate.epoch));
    }
    return ok;
  }

  /// Disconnects the control channel and disarms the watchdog.
  /// 断开控制通道并撤防看门狗。
  Future<void> disconnect() async {
    _disarmWatchdog();
    await _channel.disconnect();
    _deviceId = null;
  }

  /// Releases resources. / 释放资源。
  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _eventsCtrl.close();
  }

  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(watchdogTimeout, _onWatchdog);
  }

  void _disarmWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  Future<void> _keepalive() async {
    if (!_accepts(_commandEpoch)) {
      // The link or app was suspended since the command was accepted: drop it
      // instead of replaying a velocity the operator can no longer see.
      // 指令被接受之后链路或应用被暂停：丢弃它，而不是补发一个操作者已经看不到
      // 的速度。
      _disarmWatchdog();
      _currentVelocity = const Velocity();
      return;
    }
    if (!_channel.isConnected) {
      // Link loss is treated exactly like a command timeout.
      // 断链与指令超时同等处理。
      _onWatchdog();
      return;
    }
    if (_currentVelocity.isZero) {
      _disarmWatchdog();
      return;
    }
    final sent = await _channel.sendVelocity(_currentVelocity);
    if (!sent) {
      _onWatchdog();
      return;
    }
    _lastCommandAt = DateTime.now();
    _armWatchdog();
  }

  /// Emits a device event, ignoring late emissions after disposal.
  /// 发送设备事件；已释放后迟到的发送被忽略。
  ///
  /// Keep-alive commands run as unawaited futures, so one can still be in
  /// flight while [dispose] closes the sink — without this guard the late
  /// emission would throw "Bad state: Cannot add event after closing".
  /// 保活指令以不等待的 future 运行，[dispose] 关闭 sink 时可能仍有指令在飞行中
  /// ——没有这层守卫，迟到的投递会抛出 "Bad state: Cannot add event after closing"。
  void _emit(DeviceEvent event) {
    if (_disposed || _eventsCtrl.isClosed) return;
    _eventsCtrl.add(event);
  }

  /// Whether a command stamped with [epoch] may run right now.
  /// 盖有 [epoch] 戳的指令当前是否可以执行。
  bool _accepts(int epoch) {
    final gate = _gate;
    if (gate == null) return true;
    return gate.accepts(epoch);
  }

  /// Records a dropped (never replayed) command. / 记录一条被丢弃（绝不补发）的指令。
  void _dropStale(int epoch) {
    final gate = _gate;
    if (gate == null) return;
    gate.noteDiscarded(reason: 'staleEpoch');
    _emit(
      RobotStaleCommandDropped(
        deviceId: _deviceId ?? '',
        epoch: epoch,
        currentEpoch: gate.epoch,
      ),
    );
  }

  void _onWatchdog() {
    _disarmWatchdog();
    _currentVelocity = const Velocity();
    _watchdogTripped = true;
    // Best-effort stop; the robot must also stop on its own timeout.
    // 尽力停车；机器人端自身也应设超时停车。
    unawaited(_channel.sendStop());
    _emit(
      RobotWatchdogTriggered(
        deviceId: _deviceId ?? '',
        sinceLastCommand: _lastCommandAt == null
            ? watchdogTimeout
            : DateTime.now().difference(_lastCommandAt!),
      ),
    );
  }
}

/// Converts normalized joystick offsets to a clamped velocity.
/// 将归一化摇杆偏移转换为限幅后的速度。
///
/// Screen coordinates: `dy` grows downward, so it is negated for forward
/// motion. / 屏幕坐标 `dy` 向下为正，前进方向需取反。
Velocity velocityFromJoystick({
  required double dx,
  required double dy,
  required double maxLinear,
  required double maxAngular,
}) {
  final linear = (-dy).clamp(-1.0, 1.0).toDouble() * maxLinear;
  final angular = dx.clamp(-1.0, 1.0).toDouble() * maxAngular;
  return Velocity(linear: linear, angular: angular);
}
