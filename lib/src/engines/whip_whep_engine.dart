import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../core/rtc_engine.dart';
import '../core/rtc_events.dart';
import '../core/rtc_role.dart';
import '../core/rtc_session.dart';
import '../core/rtc_signaling.dart';
import '../core/rtc_stats.dart';
import '../publishers/local_publisher.dart';
import '../resilience/relay_policy.dart';
import '../subscribers/remote_subscriber.dart';
import 'whep_subscriber.dart';
import 'whip_client.dart';
import 'whip_whep_publisher.dart';

/// WHIP/WHEP engine over `flutter_webrtc` (bare WebRTC, maximum control).
/// 基于 `flutter_webrtc` 的 WHIP/WHEP 引擎（裸 WebRTC，最大控制力）。
///
/// Ideal for self-hosted SRS / ZLMediaKit / MediaMTX and IoT camera playback;
/// use [LiveKitEngine] for interactive rooms that need frequent track changes.
/// 适合自建 SRS / ZLMediaKit / MediaMTX 与 IoT 摄像头播放；需要频繁增减轨道的
/// 互动房间请使用 [LiveKitEngine]。
class WhipWhepEngine extends RtcEngine {
  WhipWhepEngine(this._signaling, {String? identity, Logger? logger})
    : _identity =
          identity ?? 'web-${Random().nextInt(1 << 32).toRadixString(16)}',
      _logger = logger ?? Logger('WhipWhepEngine');

  final WhipWhepSignaling _signaling;
  final String _identity;
  final Logger _logger;

  final StreamController<RtcEvent> _eventsCtrl =
      StreamController<RtcEvent>.broadcast();
  final List<WhipWhepSession> _sessions = <WhipWhepSession>[];

  @override
  RtcEngineType get type => RtcEngineType.whipWhep;

  @override
  Stream<RtcEvent> get events => _eventsCtrl.stream;

  @override
  Future<RtcSession> join({
    required String roomId,
    required RtcRole role,
    String? identity,
  }) async {
    final session = WhipWhepSession(
      engine: this,
      signaling: _signaling,
      roomId: roomId,
      role: role,
      identity: identity ?? _identity,
      logger: _logger,
    );
    _sessions.add(session);
    return session;
  }

  @override
  Future<void> dispose() async {
    for (final session in _sessions.toList()) {
      await session.dispose();
    }
    _sessions.clear();
    await _eventsCtrl.close();
  }
}

/// A WHIP/WHEP session. / 一个 WHIP/WHEP 会话。
///
/// For publish-capable roles the session owns a [LocalPublisher]; viewers
/// subscribe stream by stream through WHEP.
/// 对于可发布角色，会话持有 [LocalPublisher]；观众端通过 WHEP 逐流订阅。
class WhipWhepSession extends RtcSession implements IceRestartable {
  WhipWhepSession({
    required this.engine,
    required WhipWhepSignaling signaling,
    required String roomId,
    required RtcRole role,
    required String identity,
    Logger? logger,
  }) : _signaling = signaling,
       _roomId = roomId,
       _logger = logger ?? Logger('WhipWhepSession'),
       _role = ValueNotifier<RtcRole>(role) {
    _client = WhipWhepClient(
      whipUrl: signaling.whipUrl,
      whepUrl: signaling.whepUrl,
      headers: signaling.headers,
      streamQueryParam: signaling.streamQueryParam,
      timeout: signaling.requestTimeout,
    );
    if (role.canPublish) {
      _publisher = WhipWhepPublisher(session: this, logger: _logger);
    }
    _eventsCtrl.add(RtcConnected(roomId: roomId, role: role));
    _startStatsLoop();
  }

  final WhipWhepEngine engine;
  final WhipWhepSignaling _signaling;
  final String _roomId;
  final Logger _logger;

  late final WhipWhepClient _client;
  final ValueNotifier<RtcRole> _role;
  final StreamController<RtcEvent> _eventsCtrl =
      StreamController<RtcEvent>.broadcast();
  final StreamController<List<RemoteStream>> _remoteStreamsCtrl =
      StreamController<List<RemoteStream>>.broadcast();
  final StreamController<RtcStats> _statsCtrl =
      StreamController<RtcStats>.broadcast();
  final Map<String, WhepSubscriber> _subscribers = <String, WhepSubscriber>{};
  WhipWhepPublisher? _publisher;
  Timer? _statsTimer;
  bool _disposed = false;

  @override
  String get roomId => _roomId;

  @override
  ValueNotifier<RtcRole> get role => _role;

  @override
  LocalPublisher? get localPublisher => _publisher;

  @override
  Stream<List<RemoteStream>> get remoteStreams => _remoteStreamsCtrl.stream;

  @override
  Stream<RtcEvent> get events => _eventsCtrl.stream;

  @override
  Stream<RtcStats> get stats => _statsCtrl.stream;

  /// ICE servers for peer connections. / peer connection 使用的 ICE 服务器。
  List<IceServer> get iceServers => _signaling.iceServers;

  /// WHIP/WHEP client (shared by publisher and subscribers). / WHIP/WHEP 客户端（推流器与订阅器共用）。
  WhipWhepClient get client => _client;

  @override
  Future<RemoteSubscriber> subscribe({
    required String streamId,
    VideoQuality quality = VideoQuality.auto,
  }) async {
    _ensureNotDisposed();
    final existing = _subscribers[streamId];
    if (existing != null) return existing;
    final subscriber = WhepSubscriber(
      session: this,
      streamId: streamId,
      quality: quality,
      logger: _logger,
    );
    await subscriber.start();
    _subscribers[streamId] = subscriber;
    _publishRemoteStreams();
    _eventsCtrl.add(
      RtcTrackSubscribed(streamId: streamId, kind: RtcTrackKind.video),
    );
    return subscriber;
  }

  @override
  Future<void> unsubscribe(String streamId) async {
    final subscriber = _subscribers.remove(streamId);
    if (subscriber == null) return;
    await subscriber.dispose();
    _publishRemoteStreams();
    _eventsCtrl.add(
      RtcTrackUnsubscribed(streamId: streamId, kind: RtcTrackKind.video),
    );
  }

  @override
  Future<void> leave() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscriber in _subscribers.values.toList()) {
      await subscriber.dispose();
    }
    _subscribers.clear();
    await _publisher?.dispose();
    _publisher = null;
    _stopStatsLoop();
    _eventsCtrl.add(const RtcDisconnected(reason: 'left'));
    _publishRemoteStreams();
  }

  @override
  Future<void> dispose() async {
    await leave();
    await _eventsCtrl.close();
    await _remoteStreamsCtrl.close();
    await _statsCtrl.close();
    _role.dispose();
  }

  /// Emits an event on the session stream. / 向会话事件流发送事件。
  @override
  void emit(RtcEvent event) => _eventsCtrl.add(event);

  /// Emits an error event. / 发送错误事件。
  void emitError(
    Object error, {
    String code = RtcErrorCodes.unknown,
    RtcErrorSeverity severity = RtcErrorSeverity.recoverable,
  }) {
    final exception = error is RtcException
        ? error
        : RtcException(code: code, message: error.toString(), cause: error);
    _logger.warning('session error: $exception');
    _eventsCtrl.add(RtcError(error: exception));
  }

  /// Restarts ICE after a network handover (Wi-Fi ↔ cellular) or a failed
  /// direct attempt. / 网络切换（Wi-Fi ↔ 蜂窝）或直连失败后重启 ICE。
  ///
  /// WHIP/WHEP forbids renegotiation (RFC 9725), so the peer connections are
  /// rebuilt against the server with a fresh ICE configuration — including
  /// `iceTransportPolicy: relay` when TURN is forced.
  /// WHIP/WHEP 禁止重协商（RFC 9725），因此这里用全新的 ICE 配置重建 peer
  /// connection——强制 TURN 时还会带上 `iceTransportPolicy: relay`。
  @override
  Future<void> restartIce({RelayMode mode = RelayMode.auto}) async {
    _ensureNotDisposed();
    final planner = RelayPlanner(servers: iceServers);
    // Forcing relay without a TURN server would guarantee failure.
    // 没有 TURN 却强制中继必然失败。
    final effective = mode == RelayMode.forced && !planner.hasTurn
        ? RelayMode.auto
        : mode;
    final configuration = planner.configurationFor(
      effective,
      extra: const <String, dynamic>{
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
      },
    );
    _logger.fine('restarting ICE (${effective.name}) for room $roomId');
    await _publisher?.restartIce(configuration);
    for (final subscriber in _subscribers.values.toList()) {
      await subscriber.restart(iceConfiguration: configuration);
    }
  }

  /// Re-points an existing subscription to a variant stream id (clarity switch
  /// on single-layer servers). Returns false when the variant does not exist.
  /// 将既有订阅改指向变体流 id（单层服务端的清晰度切换）。变体不存在时返回 false。
  Future<bool> switchToVariantStream(
    RemoteSubscriber current,
    String candidateStreamId,
    ClarityLevel level,
  ) async {
    if (current is! WhepSubscriber) return false;
    final candidate = WhepSubscriber(
      session: this,
      streamId: current.streamId,
      resourceStreamId: candidateStreamId,
      quality: level,
      logger: _logger,
    );
    try {
      await candidate.start();
    } catch (e) {
      await candidate.dispose();
      _logger.fine('variant stream $candidateStreamId unavailable: $e');
      return false;
    }
    await current.dispose();
    _subscribers[current.streamId] = candidate;
    _publishRemoteStreams();
    return true;
  }

  void _publishRemoteStreams() {
    if (_disposed && _subscribers.isEmpty) {
      _remoteStreamsCtrl.add(const <RemoteStream>[]);
      return;
    }
    _remoteStreamsCtrl.add(
      _subscribers.values
          .map(
            (s) => RemoteStream(
              streamId: s.streamId,
              participantId: null,
              kinds: const <RtcTrackKind>{
                RtcTrackKind.video,
                RtcTrackKind.audio,
              },
            ),
          )
          .toList(),
    );
  }

  void _startStatsLoop() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _collectStats();
    });
  }

  void _stopStatsLoop() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _collectStats() async {
    if (_disposed) return;
    final publisher = _publisher;
    if (publisher != null) {
      final video = await publisher.sampleVideoStats();
      if (video != null) {
        _statsCtrl.add(video);
        _eventsCtrl.add(RtcStatsUpdated(stats: video));
      }
      final audio = await publisher.sampleAudioStats();
      if (audio != null) {
        _statsCtrl.add(audio);
        _eventsCtrl.add(RtcStatsUpdated(stats: audio));
      }
    }
    for (final subscriber in _subscribers.values.toList()) {
      final video = await subscriber.sampleVideoStats();
      if (video != null) {
        _statsCtrl.add(video);
        _eventsCtrl.add(RtcStatsUpdated(stats: video));
      }
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Session for room $roomId has been disposed.');
    }
  }
}
