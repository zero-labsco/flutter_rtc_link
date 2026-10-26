import 'dart:async';

import 'package:flutter/widgets.dart';

import 'link_policy.dart';

/// Maps Flutter lifecycle states to a background flag.
/// 把 Flutter 生命周期状态映射为后台标志。
class AppLifecycleGate with WidgetsBindingObserver {
  AppLifecycleGate({
    required this.onBackgroundChanged,
    this.policy = const BackgroundPolicy(),
  });

  /// Called with `true` when the app loses the foreground and `false` when it
  /// comes back. / 应用失去前台时以 `true` 回调，回到前台时以 `false` 回调。
  final Future<void> Function(bool background) onBackgroundChanged;

  /// Background behaviour. / 后台行为策略。
  final BackgroundPolicy policy;

  bool _backgrounded = false;
  bool _attached = false;
  // Serialises `handle` so a rapid background→foreground toggle cannot run the
  // two `onBackgroundChanged` callbacks out of order (which would tear the link
  // down after the app came back). / 串行化 `handle`，避免快速的"后台→前台"切换
  // 让两个 `onBackgroundChanged` 回调乱序执行（那会在应用已回到前台后错误地
  // 拆除链路）。
  Future<void>? _chain;

  /// Whether the app is currently considered backgrounded.
  /// 应用当前是否被视为处于后台。
  bool get isBackgrounded => _backgrounded;

  /// Whether the observer is attached to the binding. / 观察者是否已挂到 binding。
  bool get isAttached => _attached;

  /// Whether [state] counts as background. / [state] 是否算作后台。
  ///
  /// `hidden` (Flutter 3.13+) covers "visible but not interactive" — for a
  /// teleoperation app that is already too late to keep driving, so it is
  /// treated as background. `detached` means the engine is gone entirely.
  /// `hidden`（Flutter 3.13+）表示"可见但不可交互"——对遥控应用来说这已经
  /// 不适合继续操控，因此按后台处理；`detached` 表示引擎已被完全移除。
  static bool isBackground(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        return false;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        return true;
    }
  }

  /// Starts observing lifecycle changes. / 开始观测生命周期变化。
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Stops observing. / 停止观测。
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Applies a lifecycle state (also usable from tests or from a custom
  /// binding). / 应用一个生命周期状态（测试或自定义 binding 也可使用）。
  Future<void> handle(AppLifecycleState state) async {
    final background = isBackground(state);
    if (background == _backgrounded) return;
    // Lock the target state synchronously so a concurrent toggle observes the
    // new value and queues behind this transition instead of returning early
    // (which would have left the link torn down after the app returned to the
    // foreground). The callbacks then run strictly in order.
    // 同步锁定目标状态，使并发切换观察到新值并排在本次之后，而非提前返回
    // （否则应用回到前台后链路会被错误地拆除）。回调随后严格按序执行。
    _backgrounded = background;
    final prev = _chain;
    final completer = Completer<void>();
    _chain = completer.future;
    try {
      await prev;
      await onBackgroundChanged(background);
    } finally {
      // Always release the chain, even when the callback throws.
      // 即使回调抛异常也始终释放链。
      completer.complete();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(handle(state));
  }
}
