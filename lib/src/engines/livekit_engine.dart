import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart';

import '../core/rtc_engine.dart';
import '../core/rtc_events.dart';
import '../core/rtc_role.dart';
import '../core/rtc_session.dart';
import '../core/rtc_signaling.dart';
import '../core/rtc_stats.dart';
import '../publishers/local_publisher.dart';
import '../subscribers/remote_subscriber.dart';
import 'livekit_publisher.dart';
import 'livekit_subscriber.dart';

/// LiveKit engine (room semantics: publish/subscribe/simulcast/events).
/// LiveKit 引擎（房间语义：发布 / 订阅 / simulcast / 事件）。
///
/// Preferred for interactive scenarios (talk shows, live audience, robot video
/// return) where tracks are added and removed frequently.
/// 连麦、直播围观、机器人视频回传等需要频繁增减轨道的互动场景首选。
class LiveKitEngine extends RtcEngine {
  LiveKitEngine(this._signaling, {String? identity, Logger? logger})
    : _logger = logger ?? Logger('LiveKitEngine');

  final LiveKitSignaling _signaling;
  final Logger _logger;

  final StreamController<RtcEvent> _eventsCtrl =
      StreamController<RtcEvent>.broadcast();
  final List<LiveKitSession> _sessions = <LiveKitSession>[];

  @override
  RtcEngineType get type => RtcEngineType.livekit;

  @override
  Stream<RtcEvent> get events => _eventsCtrl.stream;

  @override
  Future<RtcSession> join({
    required String roomId,
    required RtcRole role,
    String? identity,
  }) async {
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: _signaling.adaptiveStream,
        dynacast: _signaling.dynacast,
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: capturePresetFor(_signaling.maxPublishClarity),
        ),
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          simulcast: _signaling.publishSimulcast,
          videoSimulcastLayers: simulcastLayersFor(
            _signaling.maxPublishClarity,
          ),
        ),
      ),
    );
    final token = await _signaling.tokenFactory();
    await room.connect(
      _signaling.url,
      token,
      connectOptions: lk.ConnectOptions(
        autoSubscribe: _signaling.autoSubscribe,
      ),
    );
    final session = LiveKitSession(
      engine: this,
      room: room,
      roomId: roomId,
      role: role,
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

/// Camera capture preset for a publish clarity cap. / 发布清晰度上限对应的采集预设。
lk.VideoParameters capturePresetFor(ClarityLevel level) {
  switch (level) {
    case ClarityLevel.auto:
    case ClarityLevel.p1080:
      return lk.VideoParametersPresets.h1080_169;
    case ClarityLevel.p720:
      return lk.VideoParametersPresets.h720_169;
    case ClarityLevel.p540:
      return lk.VideoParametersPresets.h540_169;
    case ClarityLevel.p360:
      return lk.VideoParametersPresets.h360_169;
  }
}

/// Simulcast layers for a publish clarity cap (low layer always kept).
/// 发布清晰度上限对应的 simulcast 层（始终保留低层）。
List<lk.VideoParameters> simulcastLayersFor(ClarityLevel level) {
  switch (level) {
    case ClarityLevel.auto:
    case ClarityLevel.p1080:
      return <lk.VideoParameters>[
        lk.VideoParametersPresets.h180_169,
        lk.VideoParametersPresets.h540_169,
        lk.VideoParametersPresets.h1080_169,
      ];
    case ClarityLevel.p720:
      return <lk.VideoParameters>[
        lk.VideoParametersPresets.h180_169,
        lk.VideoParametersPresets.h540_169,
        lk.VideoParametersPresets.h720_169,
      ];
    case ClarityLevel.p540:
      return <lk.VideoParameters>[
        lk.VideoParametersPresets.h180_169,
        lk.VideoParametersPresets.h540_169,
      ];
    case ClarityLevel.p360:
      return <lk.VideoParameters>[
        lk.VideoParametersPresets.h180_169,
        lk.VideoParametersPresets.h360_169,
      ];
  }
}

/// A LiveKit room session. / 一个 LiveKit 房间会话。
class LiveKitSession extends RtcSession {
  LiveKitSession({
    required this.engine,
    required lk.Room room,
    required String roomId,
    required RtcRole role,
    Logger? logger,
  }) : _room = room,
       _roomId = roomId,
       _logger = logger ?? Logger('LiveKitSession'),
       _role = ValueNotifier<RtcRole>(role) {
    _publisher = role.canPublish ? LiveKitPublisher(session: this) : null;
    _listener = room.createListener();
    _bindRoomEvents();
    _publishRemoteStreams();
    _eventsCtrl.add(RtcConnected(roomId: roomId, role: role));
  }

  final LiveKitEngine engine;
  final lk.Room _room;
  final String _roomId;
  final Logger _logger;
  final ValueNotifier<RtcRole> _role;
  final StreamController<RtcEvent> _eventsCtrl =
      StreamController<RtcEvent>.broadcast();
  final StreamController<List<RemoteStream>> _remoteStreamsCtrl =
      StreamController<List<RemoteStream>>.broadcast();
  final StreamController<RtcStats> _statsCtrl =
      StreamController<RtcStats>.broadcast();
  final Map<String, LiveKitSubscriber> _subscribers =
      <String, LiveKitSubscriber>{};
  // Accumulated wanted track sids per remote participant so that subscribing a
  // second stream never revokes the first one.
  // 按远端参与者维护想要的轨道 sid 集合，避免订阅第二路时撤销第一路。
  final Map<String, Set<String>> _wantedSids = <String, Set<String>>{};
  late final lk.EventsListener<lk.RoomEvent> _listener;
  LiveKitPublisher? _publisher;
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

  /// Underlying LiveKit room (advanced escape hatch). / 底层 LiveKit 房间（高级逃生口）。
  lk.Room get room => _room;

  @override
  Future<RemoteSubscriber> subscribe({
    required String streamId,
    VideoQuality quality = VideoQuality.auto,
  }) async {
    _ensureNotDisposed();
    final existing = _subscribers[streamId];
    if (existing != null) return existing;
    final publication = findPublication(streamId);
    if (publication == null) {
      throw RtcException(
        code: RtcErrorCodes.resourceNotFound,
        message: 'No published track with sid $streamId in room $roomId.',
      );
    }
    if (!publication.subscribed &&
        _room.connectionState == lk.ConnectionState.connected) {
      await _grantTrackPermission(publication, streamId);
    }
    final subscriber = LiveKitSubscriber(
      publication: publication,
      quality: quality,
    );
    _subscribers[streamId] = subscriber;
    _publishRemoteStreams();
    _eventsCtrl.add(
      RtcTrackSubscribed(streamId: streamId, kind: _kindOf(publication)),
    );
    return subscriber;
  }

  @override
  Future<void> unsubscribe(String streamId) async {
    final subscriber = _subscribers.remove(streamId);
    if (subscriber == null) return;
    for (final entry in _wantedSids.entries) {
      entry.value.remove(streamId);
    }
    await subscriber.dispose();
    _publishRemoteStreams();
    _eventsCtrl.add(
      RtcTrackUnsubscribed(streamId: streamId, kind: RtcTrackKind.video),
    );
    await _regrantWanted();
  }

  @override
  Future<void> leave() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscriber in _subscribers.values.toList()) {
      await subscriber.dispose();
    }
    _subscribers.clear();
    _wantedSids.clear();
    await _publisher?.dispose();
    _publisher = null;
    await _listener.dispose();
    await _room.disconnect();
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

  /// Finds a remote video publication by track sid. / 按 track sid 查找远端视频 publication。
  lk.RemoteTrackPublication<lk.RemoteVideoTrack>? findPublication(
    String streamId,
  ) {
    for (final participant in _room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.sid == streamId) return publication;
      }
    }
    return null;
  }

  /// Emits an event on the session stream. / 向会话事件流发送事件。
  @override
  void emit(RtcEvent event) => _eventsCtrl.add(event);

  void _bindRoomEvents() {
    _listener
      ..on<lk.RoomConnectedEvent>((_) {
        _eventsCtrl.add(RtcConnected(roomId: _roomId, role: _role.value));
      })
      ..on<lk.RoomReconnectingEvent>((_) {
        _eventsCtrl.add(
          const RtcConnectionStateChanged(
            state: RtcConnectionState.reconnecting,
          ),
        );
        _eventsCtrl.add(const RtcReconnecting(attempt: 1));
      })
      ..on<lk.RoomReconnectedEvent>((_) {
        _eventsCtrl.add(const RtcReconnected());
        _eventsCtrl.add(
          const RtcConnectionStateChanged(state: RtcConnectionState.connected),
        );
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        _eventsCtrl.add(RtcDisconnected(reason: event.reason?.toString()));
      })
      ..on<lk.ParticipantConnectedEvent>((event) {
        _eventsCtrl.add(
          RtcParticipantJoined(identity: event.participant.identity),
        );
        _publishRemoteStreams();
      })
      ..on<lk.ParticipantDisconnectedEvent>((event) {
        _eventsCtrl.add(
          RtcParticipantLeft(identity: event.participant.identity),
        );
        _publishRemoteStreams();
      })
      ..on<lk.TrackSubscribedEvent>((event) {
        _eventsCtrl.add(
          RtcTrackSubscribed(
            streamId: event.publication.sid,
            kind: _kindOf(event.publication),
          ),
        );
        _publishRemoteStreams();
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        _eventsCtrl.add(
          RtcTrackUnsubscribed(
            streamId: event.publication.sid,
            kind: _kindOf(event.publication),
          ),
        );
        _publishRemoteStreams();
      })
      ..on<lk.TrackMutedEvent>((event) {
        _eventsCtrl.add(
          RtcTrackMuteChanged(
            streamId: event.publication.sid,
            kind: _kindOf(event.publication),
            muted: true,
          ),
        );
      })
      ..on<lk.TrackUnmutedEvent>((event) {
        _eventsCtrl.add(
          RtcTrackMuteChanged(
            streamId: event.publication.sid,
            kind: _kindOf(event.publication),
            muted: false,
          ),
        );
      })
      ..on<lk.TrackSubscriptionExceptionEvent>((event) {
        _logger.warning('track subscription failed: ${event.reason}');
        _eventsCtrl.add(
          RtcError(
            error: RtcException(
              code: RtcErrorCodes.signalingFailed,
              message: 'Track subscription failed: ${event.reason}.',
            ),
          ),
        );
      })
      ..on<lk.ParticipantPermissionsUpdatedEvent>((event) {
        // Server-side grant change (promote / demote) for the local participant.
        // 本地参与者的服务端授权变更（提升 / 降级）。
        final localIdentity = _room.localParticipant?.identity;
        if (event.participant.identity != localIdentity) return;
        final canPublish = event.permissions.canPublish;
        final next = canPublish ? RtcRole.coHost : RtcRole.viewer;
        final previous = _role.value;
        if (previous == next) return;
        _role.value = next;
        _eventsCtrl.add(
          RtcRoleChanged(
            identity: localIdentity ?? '',
            fromRole: previous.label,
            toRole: next.label,
          ),
        );
        if (canPublish && _publisher == null) {
          _publisher = LiveKitPublisher(session: this);
        }
      })
      ..on<lk.VideoReceiverStatsEvent>((event) {
        // The stats type is reachable through the event's public API; its
        // fields are read directly (no type import needed).
        // stats 类型可经事件的公开 API 触达；直接读取字段（无需引入该类型）。
        final stats = event.stats;
        final lost = stats.packetsLost ?? 0;
        final received = stats.packetsReceived ?? 0;
        final total = lost + received;
        final lossPercent = total <= 0 ? 0.0 : (lost / total) * 100;
        final frameHeight = (stats.frameHeight ?? 0).toInt();
        final sample = RtcStats(
          streamId: stats.streamId,
          kind: RtcTrackKind.video,
          bitrateKbps: event.currentBitrate.toDouble(),
          packetLossPercent: lossPercent,
          fps: (stats.framesPerSecond ?? 0).toDouble(),
          width: (stats.frameWidth ?? 0).toInt(),
          height: frameHeight,
          actualClarity: ClarityLevel.fromHeight(frameHeight),
          timestamp: DateTime.now(),
        );
        _addStats(sample);
        // Route the sample to the matching subscriber when one exists.
        // 若存在匹配的订阅器，把采样路由给它。
        for (final subscriber in _subscribers.values) {
          final trackId = subscriber.videoTrack?.mediaStreamTrack.id;
          if (subscriber.streamId == stats.streamId ||
              trackId == stats.streamId) {
            subscriber.addStats(sample);
          }
        }
      });
  }

  void _addStats(RtcStats stats) {
    if (_statsCtrl.isClosed) return;
    _statsCtrl.add(stats);
    _eventsCtrl.add(RtcStatsUpdated(stats: stats));
  }

  Future<void> _grantTrackPermission(
    lk.RemoteTrackPublication<lk.RemoteVideoTrack> publication,
    String streamId,
  ) async {
    // On-demand subscription: accumulate the wanted sids for this participant so
    // subscribing another stream never revokes the earlier ones.
    // 按需订阅：累加该参与者的想要 sid，避免订阅其它路时撤销已订阅的路。
    final identity = publication.participant.identity;
    _wantedSids.putIfAbsent(identity, () => <String>{}).add(streamId);
    await _regrantWanted();
  }

  /// Re-applies the accumulated track-subscription allowlist to the local
  /// participant. / 向本地参与者重新应用累加后的轨道订阅白名单。
  Future<void> _regrantWanted() async {
    final participant = _room.localParticipant;
    if (participant == null) return;
    final permissions = <lk.ParticipantTrackPermission>[];
    for (final entry in _wantedSids.entries) {
      if (entry.value.isEmpty) continue;
      permissions.add(
        lk.ParticipantTrackPermission(entry.key, false, entry.value.toList()),
      );
    }
    participant.setTrackSubscriptionPermissions(
      allParticipantsAllowed: false,
      trackPermissions: permissions,
    );
  }

  void _publishRemoteStreams() {
    if (_remoteStreamsCtrl.isClosed) return;
    final streams = <RemoteStream>[];
    for (final participant in _room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        streams.add(
          RemoteStream(
            streamId: publication.sid,
            participantId: participant.identity,
            kinds: const <RtcTrackKind>{RtcTrackKind.video},
          ),
        );
      }
      for (final publication in participant.audioTrackPublications) {
        streams.add(
          RemoteStream(
            streamId: publication.sid,
            participantId: participant.identity,
            kinds: const <RtcTrackKind>{RtcTrackKind.audio},
          ),
        );
      }
    }
    _remoteStreamsCtrl.add(streams);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Session for room $roomId has been disposed.');
    }
  }

  static RtcTrackKind _kindOf(lk.TrackPublication publication) {
    return publication.kind == lk.TrackType.AUDIO
        ? RtcTrackKind.audio
        : RtcTrackKind.video;
  }
}
