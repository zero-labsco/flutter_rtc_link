import 'teleop_channel.dart';

/// Sealed hierarchy of robot teleoperation events (independent stream).
/// 机器人遥控事件的密封层级（独立事件流）。
///
/// This lives in the robot module — not in `core/` — so that `core` stays a
/// dependency-free shared kernel and the robot module never has to reach into
/// device management (or vice versa) just to emit an event.
/// 本文件位于 robot 模块而非 `core/`：这样 `core` 才能保持零依赖的共享内核，
/// 机器人模块也不必为了发一个事件就依赖设备管理（反之亦然）。
sealed class RobotEvent {
  const RobotEvent();
}

/// Robot telemetry updated. / 机器人遥测更新。
final class RobotTelemetryUpdated extends RobotEvent {
  const RobotTelemetryUpdated({required this.telemetry});

  /// Latest telemetry snapshot. / 最新遥测快照。
  final RobotTelemetry telemetry;
}

/// Robot control was suspended (background, link loss, user pause).
/// 机器人控制被暂停（后台、断链、用户暂停）。
///
/// Any command produced before this event belongs to an older epoch and is
/// dropped instead of being replayed. / 该事件之前产生的任何指令都属于更早的
/// epoch，会被丢弃而非补发。
final class RobotControlPaused extends RobotEvent {
  const RobotControlPaused({
    required this.deviceId,
    required this.reason,
    required this.epoch,
  });

  /// Device id. / 设备 id。
  final String deviceId;

  /// Pause reason name (see `PauseReason`). / 暂停原因名（见 `PauseReason`）。
  final String reason;

  /// Epoch that invalidated every pending command. / 使所有待处理指令失效的 epoch。
  final int epoch;
}

/// Robot control resumed on a fresh epoch. / 机器人控制在新的 epoch 上恢复。
final class RobotControlResumed extends RobotEvent {
  const RobotControlResumed({required this.deviceId, required this.epoch});

  /// Device id. / 设备 id。
  final String deviceId;

  /// Newly activated epoch. / 新激活的 epoch。
  final int epoch;
}

/// A command was dropped because it was stamped with a stale epoch.
/// 指令因盖有过期的 epoch 戳而被丢弃。
final class RobotStaleCommandDropped extends RobotEvent {
  const RobotStaleCommandDropped({
    required this.deviceId,
    required this.epoch,
    required this.currentEpoch,
  });

  /// Device id. / 设备 id。
  final String deviceId;

  /// Epoch carried by the dropped command. / 被丢弃指令所携带的 epoch。
  final int epoch;

  /// Epoch currently required. / 当前要求的 epoch。
  final int currentEpoch;
}

/// Watchdog fired: no command within the timeout, the robot was stopped.
/// 看门狗触发：超时未收到指令，机器人已自动停车。
final class RobotWatchdogTriggered extends RobotEvent {
  const RobotWatchdogTriggered({
    required this.deviceId,
    required this.sinceLastCommand,
  });

  /// Device id. / 设备 id。
  final String deviceId;

  /// Time since the last accepted command. / 距最近一条被接受指令的时间。
  final Duration sinceLastCommand;
}
