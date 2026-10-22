import 'rtc_stats.dart';

/// ICE / TURN server entry. / ICE / TURN 服务器条目。
class IceServer {
  const IceServer({required this.urls, this.username, this.credential});

  /// `turn:`/`stun:` URI(s), comma-separated for multiple. / `turn:` / `stun:` URI，多个用逗号分隔。
  final String urls;

  /// TURN username. / TURN 用户名。
  final String? username;

  /// TURN credential. / TURN 凭据。
  final String? credential;

  /// Converts to the map shape expected by `flutter_webrtc`. / 转换为 `flutter_webrtc` 期望的 map 结构。
  Map<String, dynamic> toMap() => <String, dynamic>{
    'urls': urls,
    if (username != null) 'username': username,
    if (credential != null) 'credential': credential,
  };
}

/// Signaling abstraction (pluggable). / 信令抽象（可插拔）。
///
/// The plugin never runs its own signaling server: pick [WhipWhepSignaling]
/// (SRS / ZLMediaKit / MediaMTX) or [LiveKitSignaling] (LiveKit SFU), or
/// implement the engine interfaces yourself for a custom stack.
/// 插件不自带信令服务器：选择 [WhipWhepSignaling]（SRS / ZLMediaKit / MediaMTX）
/// 或 [LiveKitSignaling]（LiveKit SFU），或自行实现引擎接口对接自建服务。
sealed class RtcSignaling {
  const RtcSignaling();
}

/// WHIP / WHEP signaling (RFC 9725): HTTP ingest and play.
/// WHIP / WHEP 信令（RFC 9725）：HTTP 推流与拉流。
///
/// Endpoints (verified against server docs):
/// - SRS 5.x+: `POST /rtc/v1/whip/?app=live&stream=<id>`, `POST /rtc/v1/whep/?app=live&stream=<id>`
/// - ZLMediaKit: `POST /index/api/whip`, `POST /index/api/whep`
/// - MediaMTX: standard WHIP/WHEP
final class WhipWhepSignaling extends RtcSignaling {
  const WhipWhepSignaling({
    required this.whipUrl,
    required this.whepUrl,
    this.iceServers = const <IceServer>[],
    this.headers = const <String, String>{},
    this.streamQueryParam = 'stream',
    this.requestTimeout = const Duration(seconds: 15),
  });

  /// WHIP publish endpoint. / WHIP 推流端点。
  final String whipUrl;

  /// WHEP play endpoint. / WHEP 拉流端点。
  final String whepUrl;

  /// ICE servers (TURN is mandatory for IoT NAT traversal). / ICE 服务器（IoT NAT 穿越必须部署 TURN）。
  final List<IceServer> iceServers;

  /// Extra HTTP headers (auth, etc.). / 额外 HTTP 头（鉴权等）。
  final Map<String, String> headers;

  /// Query parameter name carrying the stream id. / 承载流 id 的查询参数名。
  final String streamQueryParam;

  /// HTTP timeout for signaling requests. / 信令请求的 HTTP 超时。
  final Duration requestTimeout;
}

/// LiveKit signaling: room WebSocket + JWT token factory.
/// LiveKit 信令：房间 WebSocket + JWT 令牌工厂。
///
/// [tokenFactory] must return a fresh token on every call — tokens expire and
/// are never hardcoded. / [tokenFactory] 每次调用都应返回新令牌——令牌会过期，且
/// 严禁硬编码。
final class LiveKitSignaling extends RtcSignaling {
  LiveKitSignaling({
    required this.url,
    required this.tokenFactory,
    this.adaptiveStream = true,
    this.dynacast = true,
    this.publishSimulcast = true,
    this.maxPublishClarity = ClarityLevel.p1080,
    this.autoSubscribe = false,
  });

  /// LiveKit server URL (`wss://…`). / LiveKit 服务器地址（`wss://…`）。
  final String url;

  /// Async JWT factory. / 异步 JWT 工厂。
  final Future<String> Function() tokenFactory;

  /// Subscriber-side adaptive stream (auto quality). / 订阅端自适应码流（自动清晰度）。
  final bool adaptiveStream;

  /// Dynacast: pause unused layers. / Dynacast：暂停无用层。
  final bool dynacast;

  /// Publish simulcast layers. / 发布端 simulcast 分层。
  final bool publishSimulcast;

  /// Publish clarity cap (simulcast top layer). / 发布清晰度上限（simulcast 最高层）。
  final ClarityLevel maxPublishClarity;

  /// Subscribe on demand (per stream) instead of auto-subscribing everything. / 按需订阅（每路单独）而非自动订阅全部。
  final bool autoSubscribe;
}
