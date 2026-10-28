import 'rtc_role.dart';
import 'rtc_stats.dart';

/// Connection state of a session. / 会话的连接状态。
enum RtcConnectionState {
  /// Not connected. / 未连接。
  disconnected,

  /// Connecting or reconnecting in progress. / 正在连接或重连。
  connecting,

  /// Connected. / 已连接。
  connected,

  /// Reconnecting after a transient failure. / 瞬断后重连。
  reconnecting,

  /// Failed (fatal for this session). / 失败（对该会话为致命）。
  failed,
}

/// Severity of an [RtcException]. / [RtcException] 的严重级别。
enum RtcErrorSeverity {
  /// Recoverable: the session keeps running, degrade gracefully. / 可恢复：会话继续运行，优雅降级。
  recoverable,

  /// Fatal: the session cannot continue. / 致命：会话无法继续。
  fatal,
}

/// Centralized error codes shared by the Dart layer and native modules.
/// 集中定义的错误码，Dart 层与原生模块共用。
class RtcErrorCodes {
  const RtcErrorCodes._();

  /// Generic failure. / 通用失败。
  static const String unknown = 'unknown';

  /// Permission denied or permanently refused. / 权限被拒或永久拒绝。
  static const String permissionDenied = 'permission_denied';

  /// Signaling negotiation failed (SDP/HTTP). / 信令协商失败（SDP / HTTP）。
  static const String signalingFailed = 'signaling_failed';

  /// ICE / connectivity failure (TURN unreachable, NAT). / ICE / 连通性失败（TURN 不可达、NAT）。
  static const String iceFailed = 'ice_failed';

  /// Media device failure (camera/mic unavailable). / 媒体设备失败（摄像头 / 麦克风不可用）。
  static const String mediaDeviceFailed = 'media_device_failed';

  /// WHIP/WHEP resource missing (deleted on server). / WHIP/WHEP 资源不存在（服务端已删除）。
  static const String resourceNotFound = 'resource_not_found';

  /// Token expired or invalid. / 令牌过期或无效。
  static const String tokenInvalid = 'token_invalid';

  /// Platform does not support the requested capability. / 平台不支持所请求的能力。
  static const String unsupported = 'unsupported';

  /// Operation timed out. / 操作超时。
  static const String timeout = 'timeout';

  /// Watchdog stopped the robot (command timeout). / 看门狗已停车（指令超时）。
  static const String watchdogTriggered = 'watchdog_triggered';

  /// Native (Kotlin/Swift) module failure. / 原生（Kotlin / Swift）模块失败。
  static const String nativeError = 'native_error';
}

/// Typed error surfaced through [RtcEvent.error]. / 通过 [RtcEvent.error] 抛出的类型化错误。
class RtcException implements Exception {
  const RtcException({
    required this.code,
    required this.message,
    this.severity = RtcErrorSeverity.recoverable,
    this.cause,
  });

  /// One of [RtcErrorCodes]. / [RtcErrorCodes] 之一。
  final String code;

  /// Human-readable, English message. / 面向人的英文信息。
  final String message;

  /// Severity. / 严重级别。
  final RtcErrorSeverity severity;

  /// Underlying error, if any. / 底层错误（如有）。
  final Object? cause;

  @override
  String toString() =>
      'RtcException($code, $severity): $message${cause != null ? ' ($cause)' : ''}';
}

/// Sealed hierarchy of session events. / 会话事件的密封层级。
///
/// Consumers must handle every subtype (the compiler enforces this for
/// `switch` expressions inside the same library).
/// 消费者必须处理所有子类型（同一 library 内的 `switch` 表达式由编译器强制）。
///
/// Device-management events live in `device/device_events.dart` and robot
/// teleoperation events in `robot/robot_events.dart`: `core` is the shared
/// kernel and must never depend on a feature module.
/// 设备管理事件位于 `device/device_events.dart`，机器人遥控事件位于
/// `robot/robot_events.dart`：`core` 是共享内核，绝不能依赖功能模块。
sealed class RtcEvent {
  const RtcEvent();
}

/// Connected to the room/session. / 已连接到房间 / 会话。
final class RtcConnected extends RtcEvent {
  const RtcConnected({required this.roomId, this.role});

  /// Room or stream session id. / 房间或流会话 id。
  final String roomId;

  /// Effective role after joining. / 加入后的生效角色。
  final RtcRole? role;
}

/// Reconnect attempt started. / 重连尝试开始。
final class RtcReconnecting extends RtcEvent {
  const RtcReconnecting({required this.attempt});

  /// Attempt number (1-based). / 尝试次数（从 1 开始）。
  final int attempt;
}

/// Reconnected successfully. / 重连成功。
final class RtcReconnected extends RtcEvent {
  const RtcReconnected();
}

/// Disconnected from the room/session. / 与房间 / 会话断开。
final class RtcDisconnected extends RtcEvent {
  const RtcDisconnected({this.reason});

  /// Optional disconnect reason. / 可选的断开原因。
  final String? reason;
}

/// Connection state changed. / 连接状态变化。
final class RtcConnectionStateChanged extends RtcEvent {
  const RtcConnectionStateChanged({required this.state});

  /// New state. / 新状态。
  final RtcConnectionState state;
}

/// A remote participant joined. / 远端参与者加入。
final class RtcParticipantJoined extends RtcEvent {
  const RtcParticipantJoined({required this.identity, this.role});

  /// Participant identity. / 参与者标识。
  final String identity;

  /// Role name if known. / 角色名（如已知）。
  final String? role;
}

/// A remote participant left. / 远端参与者离开。
final class RtcParticipantLeft extends RtcEvent {
  const RtcParticipantLeft({required this.identity});

  /// Participant identity. / 参与者标识。
  final String identity;
}

/// A remote track was subscribed. / 已订阅远端轨道。
final class RtcTrackSubscribed extends RtcEvent {
  const RtcTrackSubscribed({required this.streamId, required this.kind});

  /// Stream id. / 流 id。
  final String streamId;

  /// Track kind. / 轨道类型。
  final RtcTrackKind kind;
}

/// A remote track was unsubscribed. / 已取消订阅一路远端轨道。
final class RtcTrackUnsubscribed extends RtcEvent {
  const RtcTrackUnsubscribed({required this.streamId, required this.kind});

  /// Stream id. / 流 id。
  final String streamId;

  /// Track kind. / 轨道类型。
  final RtcTrackKind kind;
}

/// A track's mute state changed. / 轨道静音状态变化。
final class RtcTrackMuteChanged extends RtcEvent {
  const RtcTrackMuteChanged({
    required this.streamId,
    required this.kind,
    required this.muted,
  });

  /// Stream id. / 流 id。
  final String streamId;

  /// Track kind. / 轨道类型。
  final RtcTrackKind kind;

  /// Whether the track is muted now. / 当前是否静音。
  final bool muted;
}

/// A role transfer completed (promote / handover). / 角色转接完成（提升 / 交接）。
final class RtcRoleChanged extends RtcEvent {
  const RtcRoleChanged({
    required this.identity,
    required this.fromRole,
    required this.toRole,
  });

  /// Target identity. / 目标身份。
  final String identity;

  /// Previous role name. / 原角色名。
  final String fromRole;

  /// New role name. / 新角色名。
  final String toRole;
}

/// A stream relay started. / 流转接已启动。
final class RtcRelayStarted extends RtcEvent {
  const RtcRelayStarted({required this.target, required this.kind});

  /// Relay target (RTMP URL, SFU URL, …). / 转接目标（RTMP URL、SFU URL 等）。
  final String target;

  /// Relay kind (`rtmp`, `cascade`, …). / 转接类型（`rtmp`、`cascade` 等）。
  final String kind;
}

/// A stream relay stopped. / 流转接已停止。
final class RtcRelayStopped extends RtcEvent {
  const RtcRelayStopped({required this.target, required this.kind});

  /// Relay target. / 转接目标。
  final String target;

  /// Relay kind. / 转接类型。
  final String kind;
}

/// A stream relay failed. / 流转接失败。
final class RtcRelayFailed extends RtcEvent {
  const RtcRelayFailed({required this.target, required this.kind, this.error});

  /// Relay target. / 转接目标。
  final String target;

  /// Relay kind. / 转接类型。
  final String kind;

  /// Error description. / 错误描述。
  final String? error;
}

/// Periodic stats update. / 周期性 stats 更新。
final class RtcStatsUpdated extends RtcEvent {
  const RtcStatsUpdated({required this.stats});

  /// Stats snapshot. / stats 快照。
  final RtcStats stats;
}

/// A permission was denied; the feature degrades instead of crashing.
/// 权限被拒；功能降级而非崩溃。
final class RtcPermissionDenied extends RtcEvent {
  const RtcPermissionDenied({
    required this.capability,
    this.permanently = false,
  });

  /// Capability name (e.g. `camera`, `microphone`, `nearbyWifiDevices`). / 能力名（如 `camera`、`microphone`、`nearbyWifiDevices`）。
  final String capability;

  /// Whether the refusal is permanent ("don't ask again"). / 是否为永久拒绝（"不再询问"）。
  final bool permanently;
}

/// Error event with severity classification. / 带严重级别分类的错误事件。
final class RtcError extends RtcEvent {
  const RtcError({required this.error});

  /// The typed error. / 类型化错误。
  final RtcException error;
}
