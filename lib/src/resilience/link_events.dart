import '../core/rtc_events.dart';
import '../core/rtc_stats.dart';
import 'media_health.dart';
import 'network_path.dart';
import 'relay_policy.dart';

/// Lifecycle phase of a resilient link. / 韧性链路的生命周期阶段。
enum LinkPhase {
  /// Nothing established yet. / 尚未建立。
  idle,

  /// First connection in progress. / 首次连接中。
  connecting,

  /// Healthy and usable. / 健康可用。
  connected,

  /// Usable but weak (congested / stuttering). / 可用但弱（拥塞 / 卡顿）。
  degraded,

  /// Re-establishing after a failure. / 故障后重建中。
  reconnecting,

  /// Operations suspended (background, link lost, user pause).
  /// 操作已暂停（后台、断链、用户暂停）。
  paused,

  /// Budget exhausted; a manual retry is required. / 预算已耗尽，需要手动重试。
  failed,
}

/// Why operations were suspended. / 操作被暂停的原因。
enum PauseReason {
  /// The operator pressed pause. / 操作者主动暂停。
  user,

  /// The app moved to the background (or was suspended by the OS).
  /// 应用进入后台（或被系统挂起）。
  background,

  /// The device lost its network path. / 设备失去了网络路径。
  networkLost,

  /// The media/control session was dropped. / 媒体 / 控制会话被断开。
  connectionLost,

  /// The engine reported a fatal error. / 引擎上报致命错误。
  engineError,

  /// The robot watchdog fired. / 机器人看门狗触发。
  watchdog,
}

/// One-shot token that authorizes resuming after a pause.
/// 授权在暂停后恢复的一次性票据。
///
/// Tickets are bound to the epoch they would activate and expire after
/// [ResumeTicket.expiresAt], so a confirmation tapped minutes late (or one
/// belonging to an earlier pause cycle) can never wake a stale link.
/// 票据绑定在它将会激活的 epoch 上，并在 [ResumeTicket.expiresAt] 之后过期，
/// 因此迟到数分钟的确认（或属于更早一次暂停周期的确认）永远不会唤醒过期链路。
class ResumeTicket {
  const ResumeTicket({
    required this.epoch,
    required this.issuedAt,
    required this.expiresAt,
    this.reason,
  });

  /// Epoch activated by this ticket. / 该票据将激活的 epoch。
  final int epoch;

  /// Issuing time. / 签发时间。
  final DateTime issuedAt;

  /// Expiry time. / 过期时间。
  final DateTime expiresAt;

  /// Reason of the pause being lifted. / 被解除的暂停原因。
  final PauseReason? reason;

  /// Whether the ticket can still be used at [now]. / 在 [now] 时刻票据是否仍可用。
  bool isFreshAt(DateTime now) =>
      !now.isBefore(issuedAt) && !now.isAfter(expiresAt);

  /// Remaining validity at [now] (`zero` once expired). / 在 [now] 时刻的剩余有效期（过期后为 `zero`）。
  Duration remainingAt(DateTime now) {
    final remaining = expiresAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  String toString() => 'ResumeTicket(epoch $epoch, expires at $expiresAt)';
}

/// Aggregated health of a link, for UI and diagnostics.
/// 链路的聚合健康状态，供 UI 与诊断使用。
class LinkHealth {
  const LinkHealth({
    required this.phase,
    this.quality = ConnectionQualityLevel.unknown,
    this.path = const NetworkPath.unknown(),
    this.relayMode = RelayMode.auto,
    this.attempt = 0,
    this.frozenStreams = const <String>[],
    this.paused = false,
    this.message,
    required this.updatedAt,
  });

  /// Current phase. / 当前阶段。
  final LinkPhase phase;

  /// Media quality bucket. / 媒体质量档位。
  final ConnectionQualityLevel quality;

  /// Network path in use. / 正在使用的网络路径。
  final NetworkPath path;

  /// Relay strategy in use. / 正在使用的中继策略。
  final RelayMode relayMode;

  /// Reconnect attempts since the last stable link. / 自上次稳定链路以来的重连次数。
  final int attempt;

  /// Streams currently frozen. / 当前冻结的流。
  final List<String> frozenStreams;

  /// Whether operations are suspended. / 操作是否处于暂停状态。
  final bool paused;

  /// Optional human-readable detail. / 可选的可读细节。
  final String? message;

  /// When this snapshot was produced. / 该快照的生成时间。
  final DateTime updatedAt;

  /// Whether media can flow at all. / 媒体是否能够流动。
  bool get isUsable =>
      phase == LinkPhase.connected || phase == LinkPhase.degraded;

  /// Copies with the given fields replaced. / 复制并替换给定字段。
  LinkHealth copyWith({
    LinkPhase? phase,
    ConnectionQualityLevel? quality,
    NetworkPath? path,
    RelayMode? relayMode,
    int? attempt,
    List<String>? frozenStreams,
    bool? paused,
    String? message,
    DateTime? updatedAt,
  }) {
    return LinkHealth(
      phase: phase ?? this.phase,
      quality: quality ?? this.quality,
      path: path ?? this.path,
      relayMode: relayMode ?? this.relayMode,
      attempt: attempt ?? this.attempt,
      frozenStreams: frozenStreams ?? this.frozenStreams,
      paused: paused ?? this.paused,
      message: message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serializes for diagnostics reports. / 序列化以供诊断报告使用。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'phase': phase.name,
    'quality': quality.name,
    'path': path.toJson(),
    'relayMode': relayMode.name,
    'attempt': attempt,
    'frozenStreams': frozenStreams,
    'paused': paused,
    if (message != null) 'message': message,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Sealed hierarchy of resilience events (separate from [RtcEvent]).
/// 韧性事件的密封层级（与 [RtcEvent] 分离）。
sealed class LinkEvent {
  const LinkEvent();
}

/// Health snapshot changed. / 健康快照发生变化。
final class LinkHealthChanged extends LinkEvent {
  const LinkHealthChanged({required this.health});

  /// New health. / 新的健康状态。
  final LinkHealth health;
}

/// Operations were suspended. / 操作被暂停。
final class LinkPaused extends LinkEvent {
  const LinkPaused({required this.reason, required this.epoch});

  /// Why. / 原因。
  final PauseReason reason;

  /// Epoch that invalidated every pending operation. / 使所有待处理操作失效的 epoch。
  final int epoch;
}

/// A resume ticket was issued; the user must confirm it.
/// 已签发恢复票据，用户必须确认。
final class LinkResumeRequested extends LinkEvent {
  const LinkResumeRequested({required this.ticket});

  /// The ticket to confirm. / 待确认的票据。
  final ResumeTicket ticket;
}

/// Operations resumed on a fresh epoch. / 操作在新的 epoch 上恢复。
final class LinkResumed extends LinkEvent {
  const LinkResumed({required this.epoch, this.afterReconnect = false});

  /// Newly activated epoch. / 新激活的 epoch。
  final int epoch;

  /// Whether the resume happened after a reconnect. / 恢复是否发生在重连之后。
  final bool afterReconnect;
}

/// A resume attempt was rejected (stale, expired or duplicate ticket).
/// 恢复尝试被拒绝（票据过期、陈旧或重复）。
final class LinkResumeRejected extends LinkEvent {
  const LinkResumeRejected({required this.reason});

  /// Why. / 原因。
  final String reason;
}

/// A reconnect attempt was scheduled. / 已安排一次重连尝试。
final class LinkReconnectScheduled extends LinkEvent {
  const LinkReconnectScheduled({
    required this.attempt,
    required this.delay,
    required this.mode,
  });

  /// Attempt number (1-based). / 尝试序号（从 1 开始）。
  final int attempt;

  /// Delay before the attempt. / 尝试前的延迟。
  final Duration delay;

  /// Relay strategy used. / 所使用的中继策略。
  final RelayMode mode;
}

/// A reconnect attempt failed. / 一次重连尝试失败。
final class LinkReconnectFailed extends LinkEvent {
  const LinkReconnectFailed({required this.attempt, required this.error});

  /// Attempt number (1-based). / 尝试序号（从 1 开始）。
  final int attempt;

  /// Underlying error. / 底层错误。
  final Object error;
}

/// The reconnect budget is exhausted. / 重连预算已耗尽。
final class LinkGaveUp extends LinkEvent {
  const LinkGaveUp({required this.error});

  /// Fatal error. / 致命错误。
  final RtcException error;
}

/// The network path changed. / 网络路径发生变化。
final class LinkNetworkChanged extends LinkEvent {
  const LinkNetworkChanged({required this.change, required this.iceRestarted});

  /// The classified change. / 分类后的变化。
  final NetworkPathChange change;

  /// Whether ICE was restarted for it. / 是否为此重启了 ICE。
  final bool iceRestarted;
}

/// A stream's media health changed. / 某路流的媒体健康状态发生变化。
final class LinkMediaHealthChanged extends LinkEvent {
  const LinkMediaHealthChanged({required this.health});

  /// New media health. / 新的媒体健康状态。
  final MediaHealth health;
}

/// Buffered operations were dropped instead of being replayed.
/// 缓存的操作被丢弃，而不是被补发。
final class LinkOperationsDiscarded extends LinkEvent {
  const LinkOperationsDiscarded({required this.count, required this.reason});

  /// How many operations were dropped. / 被丢弃的操作数。
  final int count;

  /// Why (`paused`, `staleEpoch`, `expired`, …). / 原因（`paused`、`staleEpoch`、`expired` 等）。
  final String reason;
}
