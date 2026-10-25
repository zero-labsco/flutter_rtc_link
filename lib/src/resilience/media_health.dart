import 'dart:async';

import '../core/rtc_stats.dart';
import 'link_policy.dart';

/// What the downlink currently looks like. / 下行链路当前的表现。
enum MediaHealthIssue {
  /// Playing normally. / 播放正常。
  healthy,

  /// Jitter/loss make playback stutter. / 抖动 / 丢包导致播放卡顿。
  stuttering,

  /// The path is congested (high RTT / heavy loss). / 路径拥塞（高 RTT / 大量丢包）。
  congested,

  /// No frames are being decoded — a frozen picture. / 没有帧被解码——画面冻结。
  frozen,
}

/// What the supervisor should do about an issue. / 监控器对某问题应采取的动作。
enum MediaRecoveryAction {
  /// Nothing yet (inside the debounce window). / 暂不动作（处于去抖窗口内）。
  none,

  /// Ask the sender for a keyframe (PLI/FIR). Cheapest recovery.
  /// 向发送端请求关键帧（PLI / FIR）。代价最低的恢复手段。
  requestKeyframe,

  /// Drop one clarity level to fit the available bandwidth.
  /// 降一档清晰度以适配可用带宽。
  downgradeClarity,

  /// Rebuild the subscription (delete the WHEP resource, play again).
  /// 重建订阅（删除 WHEP 资源后重新拉流）。
  resubscribe,
}

/// Health snapshot of one stream. / 一路流的健康快照。
class MediaHealth {
  const MediaHealth({
    required this.streamId,
    required this.issue,
    required this.since,
    required this.action,
    required this.observedAt,
    this.lastStats,
  });

  /// Stream id. / 流 id。
  final String streamId;

  /// Current issue. / 当前问题。
  final MediaHealthIssue issue;

  /// When the current issue started. / 当前问题的起始时间。
  final DateTime since;

  /// Recommended recovery action. / 建议的恢复动作。
  final MediaRecoveryAction action;

  /// When this snapshot was produced. / 该快照的生成时间。
  final DateTime observedAt;

  /// Last stats sample used. / 所使用的最后一条 stats 样本。
  final RtcStats? lastStats;

  /// Whether the picture is frozen. / 画面是否冻结。
  bool get isFrozen => issue == MediaHealthIssue.frozen;

  /// Whether anything beyond waiting is required. / 是否需要除等待以外的动作。
  bool get needsRecovery => action != MediaRecoveryAction.none;

  /// How long the issue has lasted. / 该问题已持续多久。
  Duration durationAt(DateTime now) => now.difference(since);

  /// How long the picture has been frozen (`zero` when not frozen).
  /// 画面已冻结多久（未冻结时为 `zero`）。
  Duration frozenFor(DateTime now) =>
      isFrozen ? now.difference(since) : Duration.zero;
}

class _StreamState {
  _StreamState(this.since);

  MediaHealthIssue issue = MediaHealthIssue.healthy;
  MediaRecoveryAction action = MediaRecoveryAction.none;
  DateTime since;
  int badSamples = 0;
  int goodSamples = 0;
  RtcStats? lastStats;
  MediaHealth? last;
}

/// Classifies stats into a health issue with hysteresis.
/// 带滞回地把 stats 分类为健康问题。
///
/// Frozen frames are the worst user-perceived failure: the link looks "up",
/// the UI shows a picture, but nothing moves. They are detected from FPS
/// (video) and escalated from a keyframe request to a full re-subscription.
/// 画面冻结是用户感知最差的故障：链路看着"连着"，UI 也显示画面，但一动不动。
/// 它由 FPS（视频）检测，并按"请求关键帧 → 重建订阅"逐级升级。
class MediaHealthMonitor {
  MediaHealthMonitor({
    this.policy = const WeakNetworkPolicy(),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Thresholds. / 判定阈值。
  final WeakNetworkPolicy policy;

  final DateTime Function() _now;

  final Map<String, _StreamState> _states = <String, _StreamState>{};
  final StreamController<MediaHealth> _ctrl =
      StreamController<MediaHealth>.broadcast();
  bool _disposed = false;

  /// Emitted whenever a stream's issue or action changes.
  /// 当某路流的问题或动作变化时投递。
  Stream<MediaHealth> get changes => _ctrl.stream;

  /// Last known health of one stream. / 某路流最近一次的健康状态。
  MediaHealth? healthOf(String streamId) => _states[streamId]?.last;

  /// Snapshot of every tracked stream. / 所有被跟踪流的快照。
  Map<String, MediaHealth> get snapshot => <String, MediaHealth>{
    for (final entry in _states.entries)
      if (entry.value.last != null) entry.key: entry.value.last!,
  };

  /// Streams currently frozen. / 当前处于冻结状态的流。
  List<String> get frozenStreamIds => _states.entries
      .where((e) => e.value.issue == MediaHealthIssue.frozen)
      .map((e) => e.key)
      .toList();

  /// Feeds one stats sample and returns the resulting health.
  /// 喂入一条 stats 样本并返回结果健康状态。
  MediaHealth feed(RtcStats stats) {
    if (_disposed) return _snapshotFor(stats);
    final now = _now();
    final state = _states.putIfAbsent(
      stats.streamId,
      () => _StreamState(stats.timestamp),
    );
    state.lastStats = stats;
    final severity = _classify(stats);

    if (severity == MediaHealthIssue.healthy) {
      state.goodSamples++;
      state.badSamples = 0;
      if (state.issue != MediaHealthIssue.healthy &&
          state.goodSamples >= policy.recoverySamples) {
        state.issue = MediaHealthIssue.healthy;
        state.since = now;
      }
    } else {
      state.goodSamples = 0;
      state.badSamples++;
      // Detection is debounced in both directions: a single bad sample is a
      // measurement glitch, only a run of them is a real degradation.
      // 两个方向的判定都带去抖：单个坏样本只是测量毛刺，连续多个才是真实劣化。
      if (severity != state.issue && state.badSamples >= policy.frozenSamples) {
        state.issue = severity;
        state.since = now;
        state.badSamples = 0;
      }
    }

    state.action = _actionFor(state.issue, now.difference(state.since));
    final health = MediaHealth(
      streamId: stats.streamId,
      issue: state.issue,
      since: state.since,
      action: state.action,
      observedAt: now,
      lastStats: stats,
    );
    final previous = state.last;
    state.last = health;
    if (previous == null ||
        previous.issue != health.issue ||
        previous.action != health.action) {
      if (!_ctrl.isClosed) _ctrl.add(health);
    }
    return health;
  }

  /// Stops tracking a stream (unsubscribed). / 停止跟踪某路流（已取消订阅）。
  void forget(String streamId) => _states.remove(streamId);

  /// Drops all state. / 清空所有状态。
  void reset() => _states.clear();

  /// Releases resources. / 释放资源。
  void dispose() {
    _disposed = true;
    _states.clear();
    if (!_ctrl.isClosed) {
      // ignore: unawaited_futures
      _ctrl.close();
    }
  }

  MediaHealth _snapshotFor(RtcStats stats) => MediaHealth(
    streamId: stats.streamId,
    issue: MediaHealthIssue.healthy,
    since: stats.timestamp,
    action: MediaRecoveryAction.none,
    observedAt: stats.timestamp,
    lastStats: stats,
  );

  MediaHealthIssue _classify(RtcStats stats) {
    if (stats.kind == RtcTrackKind.video && stats.fps <= policy.frozenFps) {
      // A frozen picture: the path is alive but no frames are decoded.
      // 画面冻结：链路活着，但没有帧被解码。
      if (stats.bitrateKbps > 0 || stats.rttMs > 0) {
        return MediaHealthIssue.frozen;
      }
      // No bytes and no RTT yet: the stream has simply not started.
      // 既无字节也无 RTT：流还没真正开始。
      return MediaHealthIssue.healthy;
    }
    if (stats.rttMs >= policy.congestedRttMs ||
        stats.packetLossPercent >= policy.congestedLossPercent) {
      return MediaHealthIssue.congested;
    }
    if (stats.packetLossPercent >= policy.stutterLossPercent ||
        stats.jitterMs >= policy.stutterJitterMs) {
      return MediaHealthIssue.stuttering;
    }
    return MediaHealthIssue.healthy;
  }

  MediaRecoveryAction _actionFor(MediaHealthIssue issue, Duration elapsed) {
    switch (issue) {
      case MediaHealthIssue.frozen:
        if (elapsed >= policy.resubscribeAfter) {
          return MediaRecoveryAction.resubscribe;
        }
        if (elapsed >= policy.keyframeAfter) {
          return MediaRecoveryAction.requestKeyframe;
        }
        return MediaRecoveryAction.none;
      case MediaHealthIssue.congested:
      case MediaHealthIssue.stuttering:
        return elapsed >= policy.degradeAfter
            ? MediaRecoveryAction.downgradeClarity
            : MediaRecoveryAction.none;
      case MediaHealthIssue.healthy:
        return MediaRecoveryAction.none;
    }
  }
}

/// One clarity step down, never below [WeakNetworkPolicy.minClarity].
/// 下调一档清晰度，且不低于 [WeakNetworkPolicy.minClarity]。
ClarityLevel degradeClarity(
  ClarityLevel current, {
  WeakNetworkPolicy policy = const WeakNetworkPolicy(),
}) {
  const ladder = <ClarityLevel>[
    ClarityLevel.p2160,
    ClarityLevel.p1080,
    ClarityLevel.p720,
    ClarityLevel.p540,
    ClarityLevel.p360,
  ];
  final floor = ladder.indexOf(policy.minClarity);
  final index = ladder.indexOf(current);
  if (index < 0) {
    // auto (or unknown): cap at minClarity so the degrader always makes progress.
    // auto（或未知）：封顶到 minClarity，保证降级一定有效果。
    return ladder[(floor < 0 ? ladder.length - 1 : floor)];
  }
  final next = index + 1;
  if (next >= ladder.length) return current;
  if (floor >= 0 && next > floor) return ladder[floor];
  return ladder[next];
}
