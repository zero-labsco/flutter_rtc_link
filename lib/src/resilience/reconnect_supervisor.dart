import 'dart:math' as math;

import 'link_policy.dart';
import 'relay_policy.dart';

/// Backoff + attempt bookkeeping for reconnecting a lost link.
/// 断链重连的退避与尝试记账。
///
/// Two behaviours matter in production:
/// - jitter, so a fleet of devices reconnecting after a backbone outage does
///   not synchronize into a thundering herd;
/// - relay escalation, so repeated direct failures over a cross-border path
///   switch to TURN instead of burning the operator's patience.
///
/// 生产环境中有两个关键行为：
/// - 抖动，避免一批设备在骨干故障后同步重连形成重连风暴；
/// - 中继升级，跨境路径上直连反复失败时改为 TURN，而不是继续消耗操作者耐心。
class ReconnectSupervisor {
  ReconnectSupervisor({
    this.policy = const ReconnectPolicy(),
    math.Random? random,
  }) : _random = random ?? math.Random();

  /// Backoff policy. / 退避策略。
  final ReconnectPolicy policy;

  final math.Random _random;

  int _attempt = 0;
  DateTime? _lastSuccessAt;
  DateTime? _lastFailureAt;
  DateTime? _lastUpAt;

  /// Attempts made since the last success. / 自上次成功以来的尝试次数。
  int get attempt => _attempt;

  /// Whether the budget is exhausted (the next call to [scheduleNext] returns
  /// null). / 预算是否已用完（下一次 [scheduleNext] 将返回 null）。
  bool get exhausted => !policy.allowsAttempt(_attempt + 1);

  /// Relay strategy for the next attempt. / 下一次尝试的中继策略。
  RelayMode get relayMode => relayModeForAttempt(
    _attempt + 1,
    relayAfterAttempts: policy.relayAfterAttempts,
  );

  /// Relay strategy of the current (in-flight) attempt. / 当前（进行中）尝试的中继策略。
  RelayMode get currentRelayMode => relayModeForAttempt(
    _attempt,
    relayAfterAttempts: policy.relayAfterAttempts,
  );

  /// When the link last came up. / 链路最近一次恢复的时间。
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// When the link last failed. / 链路最近一次失败的时间。
  DateTime? get lastFailureAt => _lastFailureAt;

  /// Schedules the next attempt and returns the delay to wait, or `null` when
  /// the budget is exhausted (the caller must surface a fatal error).
  /// 安排下一次尝试并返回需要等待的延迟；预算耗尽时返回 `null`
  /// （调用方必须上报致命错误）。
  Duration? scheduleNext() {
    if (!policy.allowsAttempt(_attempt + 1)) return null;
    _attempt++;
    return _jittered(policy.delayForAttempt(_attempt));
  }

  /// Records a failed attempt (the delay was already consumed).
  /// 记录一次失败的尝试（延迟已消耗）。
  ///
  /// The attempt counter only resets when the link had been up for at least
  /// [ReconnectPolicy.stableWindow]; otherwise a link that flaps every few
  /// seconds would reset forever and never escalate to relay.
  /// 只有链路已稳定运行至少 [ReconnectPolicy.stableWindow] 时，尝试计数才会
  /// 重置；否则每几秒抖一次的链路会不断重置，永远无法升级到中继。
  void recordFailure({DateTime? at}) {
    final now = at ?? DateTime.now();
    _lastFailureAt = now;
    final upAt = _lastUpAt;
    if (upAt != null && now.difference(upAt) >= policy.stableWindow) {
      _attempt = 0;
      _lastUpAt = null;
    }
  }

  /// Records a successful attempt and starts the stability window.
  /// 记录一次成功尝试并启动稳定性计时窗口。
  void recordSuccess({DateTime? at}) {
    _lastSuccessAt = at ?? DateTime.now();
    _lastUpAt = _lastSuccessAt;
  }

  /// Resets the counter unconditionally (e.g. after a manual reconnect).
  /// 无条件重置计数（例如手动重连后）。
  void reset() {
    _attempt = 0;
    _lastFailureAt = null;
    _lastUpAt = null;
    _lastSuccessAt = DateTime.now();
  }

  Duration _jittered(Duration delay) {
    final ratio = policy.jitterRatio.clamp(0.0, 1.0).toDouble();
    if (ratio == 0) return delay;
    final factor = 1 - ratio + (2 * ratio * _random.nextDouble());
    final micros = (delay.inMicroseconds * factor).round();
    return Duration(microseconds: micros < 0 ? 0 : micros);
  }
}
