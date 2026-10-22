import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../core/rtc_events.dart';
import '../core/rtc_role.dart';
import '../core/rtc_session.dart';
import '../core/rtc_stats.dart';
import '../publishers/local_publisher.dart';
import '../subscribers/remote_subscriber.dart';
import 'control_link.dart';
import 'link_events.dart';
import 'link_policy.dart';
import 'media_health.dart';
import 'network_path.dart';
import 'pause_resume_gate.dart';
import 'reconnect_supervisor.dart';
import 'relay_policy.dart';

/// Builds a fresh session (called on connect and on every reconnect).
/// 构建全新会话（连接与每次重连时调用）。
typedef RtcSessionFactory =
    Future<RtcSession> Function({
      required String roomId,
      required RtcRole role,
      String? identity,
    });

/// Restarts ICE on a live session. / 在存活会话上重启 ICE。
typedef IceRestarter =
    Future<void> Function(RtcSession session, RelayMode mode);

/// Applies a clarity change decided by the supervisor.
/// 应用由监控器决定的清晰度变更。
typedef ClarityDegrader =
    Future<void> Function(RemoteSubscriber subscriber, ClarityLevel level);

/// Requests a keyframe for a frozen stream. / 为冻结的流请求关键帧。
typedef KeyframeRequester = Future<void> Function(String streamId);

/// Wiring for [ResilientSession]. / [ResilientSession] 的接线配置。
class ResilientSessionConfig {
  const ResilientSessionConfig({
    this.policy = const LinkPolicy(),
    this.relay,
    this.monitor,
    this.iceRestarter,
    this.degrader,
    this.keyframeRequester,
    this.onStopRobot,
    this.autoResumeAfterReconnect = true,
    this.logger,
  });

  /// Timing and threshold policy. / 时序与阈值策略。
  final LinkPolicy policy;

  /// TURN planner; when null the session cannot force relay.
  /// TURN 规划器；为 null 时会话无法强制中继。
  final RelayPlanner? relay;

  /// Network path monitor; when null, handover detection is off.
  /// 网络路径监测器；为 null 时不做切换检测。
  final NetworkPathMonitor? monitor;

  /// Custom ICE restart hook (defaults to [IceRestartable]).
  /// 自定义 ICE 重启钩子（默认使用 [IceRestartable]）。
  final IceRestarter? iceRestarter;

  /// Called when the supervisor downgrades a stream. / 监控器降低清晰度时回调。
  final ClarityDegrader? degrader;

  /// Called when a keyframe is needed. / 需要关键帧时回调。
  final KeyframeRequester? keyframeRequester;

  /// Called when the link is suspended and the robot must stop.
  /// 链路暂停且机器人必须停车时回调。
  final Future<void> Function()? onStopRobot;

  /// Whether a successful reconnect resumes the gate without asking the user.
  /// 重连成功后是否不经用户确认就恢复门。
  final bool autoResumeAfterReconnect;

  /// Optional logger. / 可选日志器。
  final Logger? logger;
}

/// A session that survives its own failures. / 能从自身故障中存活的会话。
///
/// It owns everything an overseas, mobile, cross-public-network link needs:
/// - supervised establishment with a connect timeout and TURN escalation;
/// - reconnect with jittered backoff and re-subscription of every stream;
/// - network handover (Wi-Fi ↔ cellular) triggering an ICE restart;
/// - weak-network detection (stutter, congestion, frozen picture) with
///   keyframe / downgrade / re-subscribe recovery;
/// - background suspension and a **two-step resume confirmation** so no
///   operation produced before the interruption is ever replayed.
///
/// 它具备海外、移动、跨公网链路所需的一切能力：
/// - 带连接超时与 TURN 升级的受控建链；
/// - 带抖动退避的重连，并对每一路流重新订阅；
/// - 网络切换（Wi-Fi ↔ 蜂窝）触发 ICE 重启；
/// - 弱网检测（卡顿、拥塞、画面冻结）并以关键帧 / 降档 / 重订阅恢复；
/// - 后台暂停与**两步恢复确认**，确保中断前产生的操作绝不补发。
class ResilientSession implements RtcSession {
  ResilientSession._({
    required String roomId,
    required RtcRole role,
    required String? identity,
    required RtcSessionFactory factory,
    required ResilientSessionConfig config,
  }) : _roomId = roomId,
       _identity = identity,
       _factory = factory,
       _config = config,
       _policy = config.policy,
       _role = ValueNotifier<RtcRole>(role),
       _supervisor = ReconnectSupervisor(policy: config.policy.reconnect),
       _mediaHealth = MediaHealthMonitor(policy: config.policy.weakNetwork),
       _router = routerFromPolicy(config.policy.control),
       _logger = config.logger ?? Logger('ResilientSession') {
    _gate = PauseResumeGate(
      requireConfirmation: _policy.background.requireResumeConfirmation,
      confirmationTimeout: _policy.background.confirmationTimeout,
      onEvent: _emitLink,
    );
    _health = LinkHealth(
      phase: LinkPhase.idle,
      path: config.monitor?.current ?? const NetworkPath.unknown(),
      updatedAt: DateTime.now(),
    );
    _healthNotifier = ValueNotifier<LinkHealth>(_health);
  }

  /// Establishes a supervised session. / 建立一条受监控的会话。
  static Future<ResilientSession> connect({
    required String roomId,
    required RtcRole role,
    required RtcSessionFactory factory,
    String? identity,
    ResilientSessionConfig config = const ResilientSessionConfig(),
  }) async {
    final session = ResilientSession._(
      roomId: roomId,
      role: role,
      identity: identity,
      factory: factory,
      config: config,
    );
    await session._start();
    return session;
  }

  final String _roomId;
  final String? _identity;
  final RtcSessionFactory _factory;
  final ResilientSessionConfig _config;
  final LinkPolicy _policy;
  final Logger _logger;

  final ValueNotifier<RtcRole> _role;
  final ReconnectSupervisor _supervisor;
  final MediaHealthMonitor _mediaHealth;
  final ControlLinkRouter _router;
  late final PauseResumeGate _gate;

  final StreamController<RtcEvent> _eventsCtrl =
      StreamController<RtcEvent>.broadcast();
  final StreamController<LinkEvent> _linkEventsCtrl =
      StreamController<LinkEvent>.broadcast();
  final StreamController<List<RemoteStream>> _remoteStreamsCtrl =
      StreamController<List<RemoteStream>>.broadcast();
  final StreamController<RtcStats> _statsCtrl =
      StreamController<RtcStats>.broadcast();
  late final ValueNotifier<LinkHealth> _healthNotifier;

  final Map<String, ClarityLevel> _wanted = <String, ClarityLevel>{};
  final Map<String, RemoteSubscriber> _subscribers =
      <String, RemoteSubscriber>{};

  RtcSession? _session;
  StreamSubscription<RtcEvent>? _eventsSub;
  StreamSubscription<RtcStats>? _statsSub;
  StreamSubscription<List<RemoteStream>>? _remoteSub;
  StreamSubscription<NetworkPath>? _pathSub;

  Timer? _retryTimer;
  Timer? _graceTimer;
  bool _recovering = false;
  bool _backgrounded = false;
  bool _disposed = false;

  late LinkHealth _health;
  ConnectionQualityLevel _quality = ConnectionQualityLevel.unknown;

  @override
  String get roomId => _roomId;

  @override
  ValueNotifier<RtcRole> get role => _role;

  @override
  LocalPublisher? get localPublisher => _session?.localPublisher;

  @override
  Stream<List<RemoteStream>> get remoteStreams => _remoteStreamsCtrl.stream;

  @override
  Stream<RtcEvent> get events => _eventsCtrl.stream;

  @override
  Stream<RtcStats> get stats => _statsCtrl.stream;

  /// Resilience events (pause/resume, handover, health, reconnect).
  /// 韧性事件（暂停 / 恢复、切换、健康、重连）。
  Stream<LinkEvent> get linkEvents => _linkEventsCtrl.stream;

  /// Live health, listenable from the UI. / 可被 UI 监听的实时健康状态。
  ValueNotifier<LinkHealth> get healthNotifier => _healthNotifier;

  /// Last health snapshot. / 最近一次健康快照。
  LinkHealth get health => _health;

  /// The pause/resume gate guarding every operation. / 守卫所有操作的暂停 / 恢复门。
  PauseResumeGate get gate => _gate;

  /// Media health monitor. / 媒体健康监控器。
  MediaHealthMonitor get mediaHealth => _mediaHealth;

  /// Control link router (low-latency path selection). / 控制链路路由器（低时延路径选择）。
  ControlLinkRouter get controlRouter => _router;

  /// Reconnect bookkeeping. / 重连记账。
  ReconnectSupervisor get supervisor => _supervisor;

  @override
  Future<RemoteSubscriber> subscribe({
    required String streamId,
    VideoQuality quality = VideoQuality.auto,
  }) async {
    final session = _requireSession();
    _wanted[streamId] = quality;
    final subscriber = await session.subscribe(
      streamId: streamId,
      quality: quality,
    );
    _subscribers[streamId] = subscriber;
    return subscriber;
  }

  @override
  Future<void> unsubscribe(String streamId) async {
    _wanted.remove(streamId);
    final subscriber = _subscribers.remove(streamId);
    _mediaHealth.forget(streamId);
    await subscriber?.dispose();
    await _session?.unsubscribe(streamId);
  }

  /// Rebuilds one subscription (frozen picture recovery).
  /// 重建某一路订阅（画面冻结恢复）。
  Future<RemoteSubscriber?> resubscribe(String streamId) async {
    final quality = _wanted[streamId] ?? VideoQuality.auto;
    final existing = _subscribers.remove(streamId);
    await existing?.dispose();
    _mediaHealth.forget(streamId);
    final session = _session;
    if (session == null) return null;
    try {
      await session.unsubscribe(streamId);
      final subscriber = await session.subscribe(
        streamId: streamId,
        quality: quality,
      );
      _subscribers[streamId] = subscriber;
      return subscriber;
    } catch (e) {
      _logger.warning('resubscribe $streamId failed: $e');
      return null;
    }
  }

  @override
  Future<void> leave() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    // Stop watching the path: an explicit leave must never trigger a
    // reconnect because the device switched networks afterwards.
    // 停止监听路径：显式离开之后，绝不能因为设备换了网络就自动重连。
    await _pathSub?.cancel();
    _pathSub = null;
    await _detachSession();
    _setPhase(LinkPhase.idle);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _release();
  }

  /// Releases every resource owned by this session.
  /// 释放本会话持有的全部资源。
  Future<void> _release() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    await _pathSub?.cancel();
    _pathSub = null;
    await _config.monitor?.stop();
    await _detachSession();
    _mediaHealth.dispose();
    _role.dispose();
    _healthNotifier.dispose();
    await _eventsCtrl.close();
    await _linkEventsCtrl.close();
    await _remoteStreamsCtrl.close();
    await _statsCtrl.close();
  }

  @override
  void emit(RtcEvent event) {
    final session = _session;
    if (session != null) {
      session.emit(event);
      return;
    }
    _emit(event);
  }

  /// Suspends operations and (optionally) the video track.
  /// 暂停操作，并（可选地）暂停视频轨道。
  ///
  /// Every operation stamped before this call is now stale and will be
  /// dropped, never replayed. / 在此调用之前盖章的所有操作立即过期，将被丢弃而非补发。
  Future<void> pause(PauseReason reason) async {
    _gate.pause(reason);
    if (reason == PauseReason.background && _policy.background.pauseVideo) {
      await _session?.localPublisher?.setVideoEnabled(false);
    }
    if (_policy.background.stopRobot && _config.onStopRobot != null) {
      await _config.onStopRobot!();
    }
    if (_health.phase == LinkPhase.connected ||
        _health.phase == LinkPhase.degraded) {
      _setPhase(LinkPhase.paused);
    }
  }

  /// Issues a resume ticket. Confirm it with [confirmResume].
  /// 签发恢复票据，随后用 [confirmResume] 确认。
  ResumeTicket requestResume() => _gate.requestResume();

  /// The ticket waiting for confirmation. / 等待确认的票据。
  ResumeTicket? get pendingResumeTicket => _gate.pendingTicket;

  /// Confirms a resume; returns false for stale/expired tickets.
  /// 确认恢复；票据过期或陈旧时返回 false。
  Future<bool> confirmResume([ResumeTicket? ticket]) async {
    final target = ticket ?? _gate.pendingTicket;
    if (target == null) return false;
    final ok = _gate.confirmResume(target);
    if (ok) {
      await _session?.localPublisher?.setVideoEnabled(true);
      _setPhase(
        _quality == ConnectionQualityLevel.poor
            ? LinkPhase.degraded
            : LinkPhase.connected,
      );
    }
    return ok;
  }

  /// App foreground/background switch. / 应用前台 / 后台切换。
  Future<void> setBackground(bool background) async {
    if (background == _backgrounded) return;
    _backgrounded = background;
    if (!background) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (_policy.background.reconnectOnForeground &&
          (_health.phase == LinkPhase.failed ||
              _health.phase == LinkPhase.reconnecting ||
              _health.phase == LinkPhase.paused)) {
        _supervisor.reset();
        _recovering = false;
        await _establish(initial: false);
      }
      if (_gate.isPaused) {
        if (_policy.background.requireResumeConfirmation) {
          _gate.requestResume();
        } else {
          _gate.resumeImmediately();
        }
      }
      return;
    }
    // Grace period: pulling down the notification shade must not tear down
    // the link. / 宽限期：下拉通知栏不应立刻拆链。
    final grace = _policy.background.gracePeriod;
    if (grace <= Duration.zero) {
      await pause(PauseReason.background);
      return;
    }
    _graceTimer?.cancel();
    _graceTimer = Timer(grace, () {
      if (!_backgrounded || _disposed) return;
      unawaited(pause(PauseReason.background));
    });
  }

  /// Whether the app is currently backgrounded. / 应用当前是否处于后台。
  bool get isBackgrounded => _backgrounded;

  /// Restarts ICE (handover) or falls back to a full reconnect.
  /// 重启 ICE（切换）或回退为整链重连。
  Future<void> restartIce({RelayMode mode = RelayMode.auto}) async {
    final session = _session;
    if (session == null) {
      await _establish(initial: false);
      return;
    }
    final restarter = _config.iceRestarter;
    try {
      if (restarter != null) {
        await restarter(session, mode);
      } else if (session is IceRestartable) {
        await (session as IceRestartable).restartIce(mode: mode);
      } else {
        await _teardownAndReconnect(PauseReason.connectionLost);
        return;
      }
    } catch (e) {
      _logger.warning('ICE restart failed: $e');
      await _teardownAndReconnect(PauseReason.connectionLost);
      return;
    }
    _logger.fine('ICE restarted (${mode.name})');
  }

  Future<void> _start() async {
    final monitor = _config.monitor;
    if (monitor != null) {
      await monitor.start();
      _pathSub = monitor.paths.listen(_onPath);
    }
    await _establish(initial: true);
  }

  Future<void> _establish({required bool initial}) async {
    _setPhase(initial ? LinkPhase.connecting : LinkPhase.reconnecting);
    final mode = _supervisor.relayMode;
    _health = _health.copyWith(relayMode: mode, updatedAt: DateTime.now());
    try {
      final session =
          await _factory(
            roomId: _roomId,
            role: _role.value,
            identity: _identity,
          ).timeout(
            _policy.connectTimeout,
            onTimeout: () => throw RtcException(
              code: RtcErrorCodes.timeout,
              message:
                  'Connecting to $_roomId timed out after '
                  '${_policy.connectTimeout.inSeconds}s.',
            ),
          );
      await _attach(session);
      _supervisor.recordSuccess();
      _recovering = false;
      _setPhase(LinkPhase.connected);
      if (!initial) {
        await _afterReconnect();
      }
    } catch (e) {
      if (initial) {
        _setPhase(LinkPhase.failed, message: e.toString());
        // `connect()` throws, so the caller never holds a reference and could
        // never dispose us — release everything here instead of leaking the
        // monitor subscription and the stream controllers.
        // `connect()` 会抛错，调用方拿不到引用也就无从释放——此处必须自行清理，
        // 否则会泄漏监听订阅与流控制器。
        _disposed = true;
        await _release();
        rethrow;
      }
      _supervisor.recordFailure();
      _emitLink(LinkReconnectFailed(attempt: _supervisor.attempt, error: e));
      _scheduleReconnect();
    }
  }

  Future<void> _attach(RtcSession session) async {
    await _detachSession();
    _session = session;
    _eventsSub = session.events.listen(
      _onSessionEvent,
      onError: (Object error) => _emit(
        RtcError(
          error: RtcException(
            code: RtcErrorCodes.unknown,
            message: error.toString(),
            cause: error,
          ),
        ),
      ),
    );
    _statsSub = session.stats.listen(_onStats);
    _remoteSub = session.remoteStreams.listen(_remoteStreamsCtrl.add);
    _role.value = session.role.value;
  }

  Future<void> _detachSession() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _statsSub?.cancel();
    _statsSub = null;
    await _remoteSub?.cancel();
    _remoteSub = null;
    for (final subscriber in _subscribers.values.toList()) {
      await subscriber.dispose();
    }
    _subscribers.clear();
    final session = _session;
    _session = null;
    if (session != null) {
      await session.leave();
    }
  }

  void _onSessionEvent(RtcEvent event) {
    _emit(event);
    switch (event) {
      case RtcDisconnected():
        unawaited(_teardownAndReconnect(PauseReason.connectionLost));
      case RtcError e:
        if (e.error.severity == RtcErrorSeverity.fatal) {
          unawaited(_teardownAndReconnect(PauseReason.engineError));
        }
      case RtcConnectionStateChanged e:
        switch (e.state) {
          case RtcConnectionState.failed:
          case RtcConnectionState.disconnected:
            unawaited(_teardownAndReconnect(PauseReason.connectionLost));
          case RtcConnectionState.connecting:
          case RtcConnectionState.reconnecting:
          case RtcConnectionState.connected:
            break;
        }
      default:
        break;
    }
  }

  Future<void> _teardownAndReconnect(PauseReason reason) async {
    if (_disposed) return;
    // `failed` = budget exhausted, `idle` = the caller left on purpose.
    // Neither may spawn a spontaneous reconnect.
    // `failed` 表示预算耗尽，`idle` 表示调用方主动离开，两者都不得触发自发重连。
    if (_health.phase == LinkPhase.failed || _health.phase == LinkPhase.idle) {
      return;
    }
    await pause(reason);
    if (_recovering) return;
    _recovering = true;
    _setPhase(LinkPhase.reconnecting);
    _emit(
      const RtcConnectionStateChanged(state: RtcConnectionState.reconnecting),
    );
    // Drop the dead session before retrying: its stats timers and tracks must
    // not keep running while we wait for the backoff.
    // 重试前先丢弃死会话：等待退避期间不应让它的 stats 定时器与轨道继续运行。
    await _detachSession();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _retryTimer?.cancel();
    final delay = _supervisor.scheduleNext();
    if (delay == null) {
      _setPhase(LinkPhase.failed, message: 'reconnect budget exhausted');
      final error = RtcException(
        code: RtcErrorCodes.iceFailed,
        message:
            'Giving up on $_roomId after ${_supervisor.attempt} reconnect '
            'attempts.',
        severity: RtcErrorSeverity.fatal,
      );
      _emitLink(LinkGaveUp(error: error));
      _emit(RtcError(error: error));
      return;
    }
    _health = _health.copyWith(
      attempt: _supervisor.attempt,
      relayMode: _supervisor.currentRelayMode,
      updatedAt: DateTime.now(),
    );
    final attempt = _supervisor.attempt;
    _emitLink(
      LinkReconnectScheduled(
        attempt: attempt,
        delay: delay,
        mode: _supervisor.currentRelayMode,
      ),
    );
    _emit(RtcReconnecting(attempt: attempt));
    _retryTimer = Timer(delay, () {
      if (_disposed) return;
      unawaited(_establish(initial: false));
    });
  }

  Future<void> _afterReconnect() async {
    final ids = _wanted.keys.toList();
    for (final id in ids) {
      if (_disposed) return;
      final quality = _wanted[id] ?? VideoQuality.auto;
      try {
        final subscriber = await _session?.subscribe(
          streamId: id,
          quality: quality,
        );
        if (subscriber != null) _subscribers[id] = subscriber;
      } catch (e) {
        _logger.warning('resubscribe $id after reconnect failed: $e');
      }
    }
    _emit(const RtcReconnected());
    if (_config.autoResumeAfterReconnect && _gate.isPaused) {
      if (_policy.background.requireResumeConfirmation) {
        _gate.requestResume();
      } else {
        _gate.resumeImmediately(afterReconnect: true);
      }
    }
  }

  void _onStats(RtcStats stats) {
    if (!_statsCtrl.isClosed) _statsCtrl.add(stats);
    _quality = connectionQualityFrom(stats);
    final health = _mediaHealth.feed(stats);
    _onMediaHealth(health);
    if (_health.phase == LinkPhase.connected &&
        (_quality == ConnectionQualityLevel.poor ||
            _quality == ConnectionQualityLevel.fair)) {
      _setPhase(LinkPhase.degraded);
    } else if (_health.phase == LinkPhase.degraded &&
        _quality == ConnectionQualityLevel.excellent) {
      _setPhase(LinkPhase.connected);
    }
    _updateHealth();
  }

  void _onMediaHealth(MediaHealth health) {
    _emitLink(LinkMediaHealthChanged(health: health));
    switch (health.action) {
      case MediaRecoveryAction.requestKeyframe:
        unawaited(
          _config.keyframeRequester?.call(health.streamId) ??
              Future<void>.value(),
        );
      case MediaRecoveryAction.downgradeClarity:
        unawaited(_degrade(health.streamId));
      case MediaRecoveryAction.resubscribe:
        unawaited(resubscribe(health.streamId));
      case MediaRecoveryAction.none:
        break;
    }
  }

  Future<void> _degrade(String streamId) async {
    final subscriber = _subscribers[streamId];
    if (subscriber == null) return;
    final next = degradeClarity(
      subscriber.clarity.value,
      policy: _policy.weakNetwork,
    );
    if (next == subscriber.clarity.value) return;
    _logger.fine('degrading $streamId to ${next.label}');
    final degrader = _config.degrader;
    if (degrader != null) {
      await degrader(subscriber, next);
      return;
    }
    await subscriber.setClarity(next);
  }

  void _onPath(NetworkPath path) {
    final change = NetworkPathChange(from: _health.path, to: path);
    if (!change.hasChange) return;
    var iceRestarted = false;
    if (change.isLost) {
      unawaited(_teardownAndReconnect(PauseReason.networkLost));
    } else if (change.isRestored &&
        (_health.phase == LinkPhase.failed ||
            _health.phase == LinkPhase.paused ||
            _health.phase == LinkPhase.reconnecting)) {
      // A brand-new path deserves a fresh budget.
      // 一条全新的路径值得一次全新的预算。
      _supervisor.reset();
      _recovering = false;
      _scheduleReconnect();
    } else if (_policy.restartIceOnHandover &&
        _health.isUsable &&
        change.requiresIceRestart(
          restartOnSameKind: _policy.restartIceOnSameKindHandover,
        )) {
      // Cellular carriers almost always sit behind CGNAT: force relay there.
      // 蜂窝运营商几乎都在 CGNAT 之后：这种情况下强制中继。
      final relay = _config.relay;
      final mode = path.kind == NetworkKind.cellular && relay != null
          ? (relay.hasTurn ? RelayMode.forced : RelayMode.auto)
          : RelayMode.auto;
      iceRestarted = true;
      unawaited(restartIce(mode: mode));
    }
    _health = _health.copyWith(path: path, updatedAt: DateTime.now());
    _emitLink(LinkNetworkChanged(change: change, iceRestarted: iceRestarted));
    _updateHealth();
  }

  void _setPhase(LinkPhase phase, {String? message}) {
    _health = LinkHealth(
      phase: phase,
      quality: _quality,
      path: _health.path,
      relayMode: _health.relayMode,
      attempt: _supervisor.attempt,
      frozenStreams: _mediaHealth.frozenStreamIds,
      paused: _gate.isPaused,
      message: message,
      updatedAt: DateTime.now(),
    );
    _pushHealth();
  }

  void _updateHealth() {
    _health = LinkHealth(
      phase: _health.phase,
      quality: _quality,
      path: _health.path,
      relayMode: _health.relayMode,
      attempt: _supervisor.attempt,
      frozenStreams: _mediaHealth.frozenStreamIds,
      paused: _gate.isPaused,
      message: _health.message,
      updatedAt: DateTime.now(),
    );
    _pushHealth();
  }

  void _pushHealth() {
    if (_healthNotifier.value != _health) {
      _healthNotifier.value = _health;
    }
    _emitLink(LinkHealthChanged(health: _health));
  }

  RtcSession _requireSession() {
    final session = _session;
    if (session == null) {
      throw StateError(
        'Session $_roomId is not connected (phase ${_health.phase.name}).',
      );
    }
    return session;
  }

  void _emit(RtcEvent event) {
    if (_disposed || _eventsCtrl.isClosed) return;
    _eventsCtrl.add(event);
  }

  void _emitLink(LinkEvent event) {
    if (_disposed || _linkEventsCtrl.isClosed) return;
    _linkEventsCtrl.add(event);
  }
}
