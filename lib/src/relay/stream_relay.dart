import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../core/rtc_engine.dart';
import '../core/rtc_events.dart';
import '../core/rtc_role.dart';
import '../core/rtc_session.dart';
import '../core/rtc_signaling.dart';
import '../engines/livekit_engine.dart';
import '../engines/livekit_subscriber.dart';
import '../engines/whep_subscriber.dart';
import '../engines/whip_whep_engine.dart';
import '../engines/whip_whep_publisher.dart';
import '../subscribers/remote_subscriber.dart';

/// Relay kind. / 转接类型。
enum StreamRelayKind {
  /// RTMP push to a third-party live platform. / 转推第三方直播平台（RTMP）。
  rtmp,

  /// Cascade to another SFU over WHIP (secondary push). / 经 WHIP 级联到另一 SFU（二次推流）。
  cascade,
}

/// LiveKit Egress configuration (server-side RTMP relay).
/// LiveKit Egress 配置（服务端 RTMP 转推）。
class LiveKitEgressConfig {
  const LiveKitEgressConfig({
    required this.baseUrl,
    this.apiKey,
    this.apiSecret,
    this.authTokenFactory,
  });

  /// LiveKit server URL, e.g. `https://livekit.example.com`. / LiveKit 服务器地址，如 `https://livekit.example.com`。
  final String baseUrl;

  /// API key for basic auth (pair with [apiSecret]). /  Basic 鉴权用的 API key（与 [apiSecret] 配对）。
  final String? apiKey;

  /// API secret for basic auth. / Basic 鉴权用的 API secret。
  final String? apiSecret;

  /// Async factory for a pre-signed service JWT (alternative to basic auth). / 预签名服务 JWT 的异步工厂（Basic 鉴权的替代）。
  final Future<String> Function()? authTokenFactory;
}

/// Handle for an active relay. / 进行中转接的句柄。
class RelayHandle {
  const RelayHandle({
    required this.kind,
    required this.target,
    required Future<void> Function() onStop,
  }) : _onStop = onStop;

  final StreamRelayKind kind;

  /// Relay target (RTMP URL, SFU URL or Egress id). / 转接目标（RTMP URL、SFU URL 或 Egress id）。
  final String target;

  final Future<void> Function() _onStop;

  /// Stops the relay. / 停止转接。
  Future<void> stop() => _onStop();
}

/// Minimal LiveKit Egress (twirp JSON) client for room-composite RTMP output.
/// 最小 LiveKit Egress（twirp JSON）客户端：房间合流 RTMP 输出。
class LiveKitEgressClient {
  LiveKitEgressClient({
    required LiveKitEgressConfig config,
    http.Client? client,
  }) : _config = config,
       _client = client ?? http.Client();

  final LiveKitEgressConfig _config;
  final http.Client _client;

  /// Starts a room-composite Egress pushing to [rtmpUrls]. / 启动房间合流 Egress，推送到 [rtmpUrls]。
  Future<String> startRoomCompositeRtmp({
    required String roomName,
    required List<String> rtmpUrls,
    String layout = 'grid',
  }) async {
    final body = <String, dynamic>{
      'room_name': roomName,
      'layout': layout,
      'output': <String, dynamic>{
        'rtmp': <String, dynamic>{'urls': rtmpUrls},
      },
    };
    final response = await _post('StartRoomCompositeEgress', body);
    final egressId = response['egress_id'];
    if (egressId is! String || egressId.isEmpty) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Egress StartRoomCompositeEgress returned no egress_id.',
      );
    }
    return egressId;
  }

  /// Stops an Egress by id. / 按 id 停止 Egress。
  Future<void> stopEgress(String egressId) async {
    await _post('StopEgress', <String, dynamic>{'egress_id': egressId});
  }

  Future<Map<String, dynamic>> _post(
    String method,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse(
      '${_baseUrl()}/twirp/livekit.egress.v1.EgressService/$method',
    );
    final request = http.Request('POST', uri)
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    final token = _config.authTokenFactory != null
        ? await _config.authTokenFactory!()
        : null;
    if (token != null && token.isNotEmpty) {
      request.headers['authorization'] = 'Bearer $token';
    } else if (_config.apiKey != null && _config.apiSecret != null) {
      final credentials = base64Encode(
        utf8.encode('${_config.apiKey}:${_config.apiSecret}'),
      );
      request.headers['authorization'] = 'Basic $credentials';
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } catch (e) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Egress request $method failed.',
        cause: e,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message:
            'Egress $method returned ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Egress $method returned a non-object body.',
      );
    }
    return decoded;
  }

  String _baseUrl() {
    var base = _config.baseUrl;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (base.startsWith('ws://')) base = base.replaceFirst('ws://', 'http://');
    if (base.startsWith('wss://')) {
      base = base.replaceFirst('wss://', 'https://');
    }
    return base;
  }
}

/// Stream relay (media-level), kept separate from [RoleTransfer] (identity).
/// 流转接（媒体层面），与 [RoleTransfer]（身份转接）分开实现。
///
/// - [toRtmp] uses the LiveKit server-side Egress (composed room → RTMP).
/// - [cascade] pulls one stream and re-publishes it over WHIP to another SFU.
///
/// - [toRtmp] 使用 LiveKit 服务端 Egress（房间合流 → RTMP）；
/// - [cascade] 拉一路流并经 WHIP 二次推流到另一个 SFU。
class StreamRelay {
  const StreamRelay._();

  static final Expando<_RelayRegistry> _registry = Expando<_RelayRegistry>();

  /// Relays the room to a third-party RTMP platform (LiveKit Egress).
  /// 将房间流转推到第三方 RTMP 平台（LiveKit Egress）。
  static Future<RelayHandle> toRtmp(
    RtcSession session,
    String rtmpUrl, {
    required LiveKitEgressConfig egress,
    String layout = 'grid',
  }) async {
    if (session is! LiveKitSession) {
      throw RtcException(
        code: RtcErrorCodes.unsupported,
        message:
            'RTMP relay via Egress requires the LiveKit engine; '
            'WHIP/WHEP sessions should relay on the server side.',
      );
    }
    final client = LiveKitEgressClient(config: egress);
    final egressId = await client.startRoomCompositeRtmp(
      roomName: session.roomId,
      rtmpUrls: <String>[rtmpUrl],
      layout: layout,
    );
    final handle = RelayHandle(
      kind: StreamRelayKind.rtmp,
      target: rtmpUrl,
      onStop: () async {
        try {
          await client.stopEgress(egressId);
        } finally {
          session.emit(RtcRelayStopped(target: rtmpUrl, kind: 'rtmp'));
        }
      },
    );
    _registryFor(session).add(handle);
    session.emit(RtcRelayStarted(target: rtmpUrl, kind: 'rtmp'));
    return handle;
  }

  /// Cascades one stream to another SFU over WHIP (secondary push).
  /// 将一路流经 WHIP 二次推流级联到另一个 SFU。
  static Future<RelayHandle> cascade(
    RtcSession session,
    String targetWhipUrl, {
    String? streamId,
    List<IceServer>? iceServers,
  }) async {
    final sourceStreamId = streamId ?? _firstVideoStreamId(session);
    if (sourceStreamId == null) {
      throw RtcException(
        code: RtcErrorCodes.resourceNotFound,
        message: 'No remote video stream to cascade; subscribe first.',
      );
    }
    final subscriber = await session.subscribe(streamId: sourceStreamId);
    final videoTrack = _resolveVideoTrack(subscriber);
    if (videoTrack == null) {
      throw RtcException(
        code: RtcErrorCodes.resourceNotFound,
        message: 'Stream $sourceStreamId has no video track to relay.',
      );
    }
    final servers = iceServers ?? _iceServersOf(session);
    final relayEngine = await RtcEngine.create(
      signaling: WhipWhepSignaling(
        whipUrl: targetWhipUrl,
        whepUrl: targetWhipUrl,
        iceServers: servers,
      ),
    );
    final relaySession = await relayEngine.join(
      roomId: '${session.roomId}-relay-$sourceStreamId',
      role: RtcRole.anchor,
    );
    final publisher = relaySession.localPublisher;
    if (publisher is! WhipWhepPublisher) {
      throw StateError('Relay session publisher has an unexpected type.');
    }
    await publisher.startRelay(videoTrack: videoTrack);
    final handle = RelayHandle(
      kind: StreamRelayKind.cascade,
      target: targetWhipUrl,
      onStop: () async {
        try {
          await relaySession.leave();
          await relayEngine.dispose();
        } finally {
          session.emit(RtcRelayStopped(target: targetWhipUrl, kind: 'cascade'));
        }
      },
    );
    _registryFor(session).add(handle);
    session.emit(RtcRelayStarted(target: targetWhipUrl, kind: 'cascade'));
    return handle;
  }

  /// Stops every active relay of [kind] on the session. / 停止会话上某类型的全部进行中转接。
  static Future<void> stop(RtcSession session, StreamRelayKind kind) async {
    final registry = _registry[session];
    if (registry == null) return;
    final handles = registry.handles.where((h) => h.kind == kind).toList();
    for (final handle in handles) {
      try {
        await handle.stop();
      } on RtcException catch (e) {
        session.emit(
          RtcRelayFailed(
            target: handle.target,
            kind: kind.name,
            error: e.message,
          ),
        );
      }
    }
    registry.removeAll(handles);
  }

  static _RelayRegistry _registryFor(RtcSession session) {
    return _registry[session] ??= _RelayRegistry();
  }

  static String? _firstVideoStreamId(RtcSession session) {
    if (session is LiveKitSession) {
      for (final participant in session.room.remoteParticipants.values) {
        for (final publication in participant.videoTrackPublications) {
          return publication.sid;
        }
      }
    }
    return null;
  }

  static List<IceServer> _iceServersOf(RtcSession session) {
    if (session is WhipWhepSession) return session.iceServers;
    return const <IceServer>[];
  }

  static MediaStreamTrack? _resolveVideoTrack(RemoteSubscriber subscriber) {
    // LiveKit subscribers expose the track directly; WHEP subscribers expose
    // the received track. Both are flutter_webrtc MediaStreamTrack instances.
    // LiveKit 订阅器直接暴露轨道；WHEP 订阅器暴露收到的轨道。两者都是
    // flutter_webrtc 的 MediaStreamTrack。
    if (subscriber is LiveKitSubscriber) {
      return subscriber.videoTrack?.mediaStreamTrack;
    }
    if (subscriber is WhepSubscriber) {
      return subscriber.receivedVideoTrack;
    }
    return null;
  }
}

class _RelayRegistry {
  final List<RelayHandle> handles = <RelayHandle>[];

  void add(RelayHandle handle) => handles.add(handle);

  void removeAll(Iterable<RelayHandle> toRemove) {
    handles.removeWhere((h) => toRemove.contains(h));
  }
}
