import 'link_events.dart';

/// Outcome of validating an operation against the gate.
/// 操作针对暂停-恢复门校验的结果。
enum OperationVerdict {
  /// The operation may run. / 操作可以执行。
  accepted,

  /// Operations are suspended. / 操作已暂停。
  paused,

  /// The operation was created before the last pause/resume cycle.
  /// 操作创建于上一次暂停 / 恢复周期之前。
  staleEpoch,

  /// A resume ticket exists but has not been confirmed yet.
  /// 恢复票据已签发但尚未确认。
  awaitingConfirmation,
}

/// The app-side pause/resume confirmation gate.
/// 应用侧的暂停 / 恢复确认门。
///
/// An robot/operator app must never replay operations that were produced
/// before an interruption: a joystick position buffered while the app was in
/// the background, a PTZ preset tapped during a reconnect, or a "start
/// recording" that survived an OS suspend would all move the machine in a
/// context the operator can no longer see.
///
/// 机器人 / 操作类应用绝不能补发中断前产生的操作：后台期间缓存的摇杆位置、
/// 重连过程中点击的云台预置位、系统挂起后仍然存活的"开始录制"，都会让机器在
/// 操作者已经看不到的场景下动作。
///
/// The rule enforced here:
/// 1. every operation is stamped with the current [epoch];
/// 2. [pause] bumps the epoch, which instantly invalidates everything stamped
///    before it — buffered operations are dropped, never replayed;
/// 3. resuming is a two-step handshake ([requestResume] → [confirmResume]);
///    the ticket is bound to the next epoch and expires, so a late or foreign
///    confirmation cannot wake the link.
///
/// 这里强制的规则：
/// 1. 每个操作都盖上当前 [epoch] 的戳；
/// 2. [pause] 递增 epoch，立即让此前所有戳失效——缓存操作被丢弃而非补发；
/// 3. 恢复是两步握手（[requestResume] → [confirmResume]）；票据绑定下一个
///    epoch 并且会过期，迟到或外来的确认无法唤醒链路。
class PauseResumeGate {
  PauseResumeGate({
    this.requireConfirmation = true,
    this.confirmationTimeout = const Duration(seconds: 30),
    DateTime Function()? clock,
    this.onEvent,
  }) : _now = clock ?? DateTime.now;

  /// Whether resuming needs an explicit confirmation.
  /// 恢复是否需要显式确认。
  final bool requireConfirmation;

  /// How long a resume ticket stays valid. / 恢复票据的有效期。
  final Duration confirmationTimeout;

  final DateTime Function() _now;

  /// Optional event sink (wire it to a UI or a log). / 可选事件出口（接到 UI 或日志）。
  final void Function(LinkEvent event)? onEvent;

  int _epoch = 1;
  bool _paused = false;
  PauseReason? _reason;
  ResumeTicket? _ticket;
  int _discarded = 0;

  /// Epoch that every new operation must carry. / 每个新操作必须携带的 epoch。
  int get epoch => _epoch;

  /// Whether operations are suspended. / 操作是否处于暂停状态。
  bool get isPaused => _paused;

  /// Whether operations may run right now. / 当前是否可以执行操作。
  bool get isActive => !_paused && _ticket == null;

  /// Whether a resume ticket is waiting for confirmation.
  /// 是否有恢复票据正在等待确认。
  bool get isAwaitingConfirmation => _ticket != null;

  /// Why operations were suspended. / 操作被暂停的原因。
  PauseReason? get pauseReason => _reason;

  /// The ticket waiting for confirmation, if any. / 等待确认的票据（如有）。
  ResumeTicket? get pendingTicket => _ticket;

  /// How many operations were dropped instead of replayed.
  /// 有多少操作被丢弃而非补发。
  int get discardedOperations => _discarded;

  /// Stamps a new operation with the current epoch. / 用当前 epoch 为新操作盖章。
  int stamp() => _epoch;

  /// Suspends operations: every pending operation becomes stale immediately.
  /// 暂停操作：所有待处理操作立即过期。
  void pause(PauseReason reason) {
    if (_paused) return;
    _paused = true;
    _reason = reason;
    _ticket = null;
    _epoch++;
    onEvent?.call(LinkPaused(reason: reason, epoch: _epoch));
  }

  /// Issues a resume ticket bound to the next epoch.
  /// 签发一张绑定下一个 epoch 的恢复票据。
  ResumeTicket requestResume() {
    final now = _now();
    final ticket = ResumeTicket(
      epoch: _epoch + 1,
      issuedAt: now,
      expiresAt: now.add(confirmationTimeout),
      reason: _reason,
    );
    _ticket = ticket;
    onEvent?.call(LinkResumeRequested(ticket: ticket));
    return ticket;
  }

  /// Confirms a resume. Returns false for unknown, expired or foreign
  /// tickets (the caller must surface that to the user).
  /// 确认恢复。票据未知、过期或不属于本周期时返回 false
  /// （调用方必须把这一点告知用户）。
  bool confirmResume(ResumeTicket ticket, {bool afterReconnect = false}) {
    if (!_paused) {
      _reject('not paused');
      return false;
    }
    final active = _ticket;
    if (active == null) {
      _reject('no ticket issued');
      return false;
    }
    if (!identical(active, ticket)) {
      _reject('foreign ticket');
      return false;
    }
    if (ticket.epoch != _epoch + 1) {
      _reject('stale ticket (epoch ${ticket.epoch} != ${_epoch + 1})');
      _ticket = null;
      return false;
    }
    final now = _now();
    if (!ticket.isFreshAt(now)) {
      _ticket = null;
      _reject('ticket expired');
      return false;
    }
    _epoch = ticket.epoch;
    _paused = false;
    _reason = null;
    _ticket = null;
    onEvent?.call(LinkResumed(epoch: _epoch, afterReconnect: afterReconnect));
    return true;
  }

  /// Resumes without confirmation (used when the interruption is over and the
  /// policy says no user interaction is needed).
  /// 无需确认直接恢复（中断已结束且策略说明无需用户交互时使用）。
  bool resumeImmediately({bool afterReconnect = false}) =>
      confirmResume(requestResume(), afterReconnect: afterReconnect);

  /// Drops the pending ticket. / 丢弃待确认票据。
  void cancelResume() {
    if (_ticket != null) {
      _ticket = null;
      onEvent?.call(const LinkResumeRejected(reason: 'cancelled'));
    }
  }

  /// Validates an operation stamped with [epoch]. / 校验盖有 [epoch] 戳的操作。
  OperationVerdict verify(int epoch) {
    if (_paused) {
      return _ticket == null
          ? OperationVerdict.paused
          : OperationVerdict.awaitingConfirmation;
    }
    if (_ticket != null) return OperationVerdict.awaitingConfirmation;
    if (epoch != _epoch) return OperationVerdict.staleEpoch;
    return OperationVerdict.accepted;
  }

  /// Whether an operation stamped with [epoch] may run.
  /// 盖有 [epoch] 戳的操作是否可以执行。
  bool accepts(int epoch) => verify(epoch) == OperationVerdict.accepted;

  /// Records that [count] operations were dropped, never replayed.
  /// 记录有 [count] 个操作被丢弃而非补发。
  void noteDiscarded({int count = 1, required String reason}) {
    _discarded += count;
    onEvent?.call(LinkOperationsDiscarded(count: count, reason: reason));
  }

  void _reject(String reason) {
    onEvent?.call(LinkResumeRejected(reason: reason));
  }
}

class _Pending<T> {
  const _Pending({
    required this.epoch,
    required this.value,
    required this.createdAt,
  });

  final int epoch;
  final T value;
  final DateTime createdAt;
}

/// Latest-wins operation buffer that can never replay stale work.
/// 永不补发过期操作的"最新者胜"缓冲区。
///
/// Teleoperation is a *state* stream, not a *command* stream: only the newest
/// joystick position matters, so a buffer of one plus an epoch check is both
/// the fastest and the safest design. Anything older than the current epoch is
/// discarded on [take].
/// 遥控是*状态*流而非*指令*流：只有最新的摇杆位置有意义，因此"容量 1 的缓冲
/// 区 + epoch 校验"既最快也最安全。[take] 时会丢弃任何早于当前 epoch 的内容。
class EpochOperationQueue<T> {
  EpochOperationQueue(
    this.gate, {
    this.maxPending = 1,
    this.maxAge,
    this.onDiscard,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Gate providing the epoch. / 提供 epoch 的门。
  final PauseResumeGate gate;

  /// Buffer depth (1 = latest wins). / 缓冲深度（1 表示最新者胜）。
  final int maxPending;

  /// Drop buffered operations older than this. / 丢弃超过该时长的缓存操作。
  final Duration? maxAge;

  /// Called for every dropped operation (metrics / UI feedback).
  /// 每个被丢弃的操作都会回调（指标 / UI 反馈）。
  final void Function(T operation, String reason)? onDiscard;

  final DateTime Function() _now;

  final List<_Pending<T>> _pending = <_Pending<T>>[];
  int _discarded = 0;
  int _coalesced = 0;

  /// Buffered operations. / 已缓存的操作数。
  int get pendingCount => _pending.length;

  /// Operations dropped because they went stale. / 因过期而丢弃的操作数。
  int get discarded => _discarded;

  /// Operations replaced by a newer one. / 被更新操作替换掉的操作数。
  int get coalesced => _coalesced;

  /// Buffers [operation]; returns false when the gate rejects it outright.
  /// 缓存 [operation]；门直接拒绝时返回 false。
  bool submit(T operation, {DateTime? at}) {
    final now = at ?? _now();
    final epoch = gate.stamp();
    if (!gate.isActive) {
      _drop(
        _Pending<T>(epoch: epoch, value: operation, createdAt: now),
        'paused',
      );
      return false;
    }
    _pending.add(_Pending<T>(epoch: epoch, value: operation, createdAt: now));
    while (_pending.length > maxPending) {
      _coalesced++;
      _drop(_pending.removeAt(0), 'coalesced');
    }
    return true;
  }

  /// Takes the next operation, or `null` when it went stale.
  /// 取出下一个操作；已过期时返回 `null`。
  T? take({DateTime? at}) {
    if (_pending.isEmpty) return null;
    final now = at ?? _now();
    final item = _pending.removeAt(0);
    final verdict = gate.verify(item.epoch);
    if (verdict != OperationVerdict.accepted) {
      _drop(item, verdict.name);
      return null;
    }
    final maxAge = this.maxAge;
    if (maxAge != null && now.difference(item.createdAt) > maxAge) {
      _drop(item, 'expired');
      return null;
    }
    return item.value;
  }

  /// Drops everything buffered. / 丢弃所有缓存的操作。
  void clear({String reason = 'cleared'}) {
    for (final item in _pending.toList()) {
      _drop(item, reason);
    }
    _pending.clear();
  }

  void _drop(_Pending<T> item, String reason) {
    _discarded++;
    gate.noteDiscarded(reason: reason);
    onDiscard?.call(item.value, reason);
  }
}
