import 'link_policy.dart';

/// Transport used by the control channel. / 控制通道所使用的传输方式。
enum ControlLinkKind {
  /// WebRTC data channel (peer to peer, LAN, lowest latency).
  /// WebRTC 数据通道（点对点、局域网、时延最低）。
  dataChannel,

  /// MQTT over the public internet (works everywhere, +1 RTT to the broker).
  /// 公网 MQTT（哪儿都能用，但多一跳到 broker 的 RTT）。
  mqtt,

  /// HTTPS request/response (last resort, never for real-time commands).
  /// HTTPS 请求 / 响应（最后手段，绝不用于实时指令）。
  http,
}

/// One candidate control path. / 一条候选控制路径。
class ControlLinkPath {
  const ControlLinkPath({
    required this.kind,
    required this.id,
    this.rttMs = 0,
    this.reachable = true,
    this.metered = false,
    this.lastAckAt,
  });

  /// Transport kind. / 传输类型。
  final ControlLinkKind kind;

  /// Path identity (topic, channel label, endpoint). / 路径标识（主题、通道名、端点）。
  final String id;

  /// Measured round-trip time in milliseconds. / 实测往返时延（毫秒）。
  final double rttMs;

  /// Whether the path is currently usable. / 该路径当前是否可用。
  final bool reachable;

  /// Whether the path costs money per byte. / 该路径是否按流量计费。
  final bool metered;

  /// When the last command was acknowledged. / 最近一次指令被确认的时间。
  final DateTime? lastAckAt;

  /// How long ago the last ack was (null when never acked).
  /// 距最近一次确认过去了多久（从未确认时为 null）。
  Duration? ageAt(DateTime now) =>
      lastAckAt == null ? null : now.difference(lastAckAt!);

  @override
  String toString() => 'ControlLinkPath(${kind.name}:$id, rtt ${rttMs}ms)';
}

/// Why a path was chosen. / 选择该路径的原因。
enum ControlLinkSelectionReason {
  /// The preferred kind (data channel) is usable. / 首选类型（数据通道）可用。
  preferredKind,

  /// Lowest measured RTT among the candidates. / 候选中实测 RTT 最低。
  lowestRtt,

  /// The only reachable path. / 唯一可达的路径。
  onlyOption,

  /// Preferred kind is gone; using whatever is left. / 首选类型不可用，使用剩余路径。
  fallback,
}

/// Result of a routing decision. / 路由决策的结果。
class ControlLinkSelection {
  const ControlLinkSelection({
    required this.path,
    required this.reason,
    required this.withinBudget,
  });

  /// Chosen path. / 选中的路径。
  final ControlLinkPath path;

  /// Why. / 原因。
  final ControlLinkSelectionReason reason;

  /// Whether the path meets the latency budget. / 该路径是否满足时延预算。
  final bool withinBudget;

  @override
  String toString() =>
      'ControlLinkSelection(${path.id}, ${reason.name}, budget: $withinBudget)';
}

/// Picks the control path with the lowest latency. / 选择时延最低的控制路径。
///
/// Overseas links are asymmetric: the data channel may die while MQTT is still
/// fine, and vice versa. The router keeps both measured and always commands on
/// the best one, which is what keeps a 200 ms budget reachable across a public
/// network.
/// 海外链路是不对称的：数据通道可能已断而 MQTT 仍然可用，反之亦然。路由器持续
/// 测量两条路径并始终在最优的一条上下发指令，这正是跨公网仍能守住 200ms 预算的
/// 原因。
class ControlLinkRouter {
  const ControlLinkRouter({
    this.preferDataChannel = true,
    this.rttBudgetMs = 200,
  });

  /// Prefer the peer-to-peer data channel when it is healthy.
  /// 数据通道健康时优先使用点对点数据通道。
  final bool preferDataChannel;

  /// Latency budget in milliseconds. / 时延预算（毫秒）。
  final int rttBudgetMs;

  /// Selects the best reachable path, or `null` when none is reachable.
  /// 选择最佳可达路径；无可达路径时返回 `null`。
  ControlLinkSelection? select(Iterable<ControlLinkPath> paths) {
    final candidates = paths.where((p) => p.reachable).toList();
    if (candidates.isEmpty) return null;

    if (candidates.length == 1) {
      return ControlLinkSelection(
        path: candidates.first,
        reason: ControlLinkSelectionReason.onlyOption,
        withinBudget: candidates.first.rttMs <= rttBudgetMs,
      );
    }

    candidates.sort((a, b) {
      if (preferDataChannel) {
        final ap = a.kind == ControlLinkKind.dataChannel ? 0 : 1;
        final bp = b.kind == ControlLinkKind.dataChannel ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
      }
      final am = a.metered ? 1 : 0;
      final bm = b.metered ? 1 : 0;
      if (am != bm) return am.compareTo(bm);
      return a.rttMs.compareTo(b.rttMs);
    });

    final best = candidates.first;
    // `onlyOption` is already handled above for the single-candidate case. Here
    // several paths are reachable, so the choice is by preferred kind or by
    // lowest RTT (even when their RTTs happen to tie).
    // `onlyOption` 已在上方单候选分支处理。此处有多条可达路径，因此按偏好类型
    // 或最低 RTT 选择（即使它们的 RTT 恰好相等）。
    final reason = preferDataChannel && best.kind == ControlLinkKind.dataChannel
        ? ControlLinkSelectionReason.preferredKind
        : ControlLinkSelectionReason.lowestRtt;
    return ControlLinkSelection(
      path: best,
      reason: reason,
      withinBudget: best.rttMs <= rttBudgetMs,
    );
  }
}

/// Exponentially weighted RTT estimate for one control path.
/// 单条控制路径的指数加权 RTT 估计。
class ControlRttTracker {
  ControlRttTracker({this.alpha = 0.25, this.initialRttMs = 0});

  /// Smoothing factor (0–1): higher reacts faster. / 平滑因子（0–1），越大反应越快。
  final double alpha;

  /// Estimate used before the first sample. / 首个样本之前使用的估计值。
  final double initialRttMs;

  double _rttMs = 0;
  int _samples = 0;

  /// Smoothed RTT in milliseconds. / 平滑后的 RTT（毫秒）。
  double get rttMs => _samples == 0 ? initialRttMs : _rttMs;

  /// How many samples were seen. / 已观测到的样本数。
  int get samples => _samples;

  /// Feeds one measurement. / 喂入一次测量值。
  void sample(double rttMs) {
    if (rttMs < 0) return;
    _rttMs = _samples == 0 ? rttMs : _rttMs + alpha * (rttMs - _rttMs);
    _samples++;
  }

  /// Whether the estimate fits [budgetMs]. / 估计值是否满足 [budgetMs] 预算。
  bool withinBudget(int budgetMs) => rttMs <= budgetMs;
}

/// Rate limiter for control commands. / 控制指令的限流器。
///
/// A joystick produces 60+ events per second; the robot only needs ~10. Sending
/// everything queues behind the link and *increases* perceived latency, so the
/// newest command wins and the rest are coalesced.
/// 摇杆每秒产生 60+ 个事件，而机器人只需要约 10 个。全量下发会在链路上排队并
/// *放大*感知时延，因此采用最新者胜、其余合并的策略。
class CommandRateLimiter {
  CommandRateLimiter({required this.minInterval, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// Minimum gap between two accepted commands. / 两条被接受指令之间的最小间隔。
  final Duration minInterval;

  final DateTime Function() _now;

  DateTime? _lastAt;
  int _dropped = 0;

  /// Commands dropped by the limiter. / 被限流器丢弃的指令数。
  int get dropped => _dropped;

  /// Whether a command may be sent now. / 当前是否可以发送指令。
  bool allow({DateTime? at}) {
    final now = at ?? _now();
    final last = _lastAt;
    if (last != null && now.difference(last) < minInterval) {
      _dropped++;
      return false;
    }
    _lastAt = now;
    return true;
  }

  /// Resets the window (e.g. after a reconnect). / 重置窗口（例如重连后）。
  void reset() {
    _lastAt = null;
  }
}

/// Builds a default router from a [ControlLinkPolicy].
/// 由 [ControlLinkPolicy] 构造默认路由器。
ControlLinkRouter routerFromPolicy(ControlLinkPolicy policy) =>
    ControlLinkRouter(
      preferDataChannel: policy.preferDataChannel,
      rttBudgetMs: policy.rttBudgetMs,
    );
