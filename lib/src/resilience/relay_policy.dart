import '../core/rtc_signaling.dart';

/// Relay (TURN) strategy for one link attempt. / 单次链路尝试的中继（TURN）策略。
enum RelayMode {
  /// Try the shortest path first (host / srflx), TURN is only a fallback.
  /// 优先走最短路径（host / srflx），TURN 仅作兜底。
  direct,

  /// Standard ICE: every candidate competes, TURN is listed first so a relay
  /// candidate is already gathered when the direct path dies.
  /// 标准 ICE：所有候选同时竞争；TURN 排在前面，直连断开时中继候选已就绪。
  auto,

  /// Relay-only. Mandatory once direct attempts across a public network keep
  /// failing: symmetric NAT, CGNAT, hotel/enterprise proxies and most
  /// cross-border paths never connect peer to peer.
  /// 仅中继。跨公网直连连续失败后必须启用：对称 NAT、CGNAT、酒店 / 企业代理
  /// 以及多数跨境路径都无法点对点连通。
  forced,
}

/// Whether [server] is a TURN (relay) server. / [server] 是否为 TURN（中继）服务器。
bool isTurnServer(IceServer server) {
  return server.urls
      .split(',')
      .any((url) => url.trim().toLowerCase().startsWith('turn'));
}

/// ICE transport policy name expected by `flutter_webrtc`.
/// `flutter_webrtc` 期望的 ICE transport policy 名称。
String iceTransportPolicyFor(RelayMode mode) =>
    mode == RelayMode.forced ? 'relay' : 'all';

/// Escalates the relay strategy as attempts fail. / 随尝试失败逐步升级中继策略。
///
/// Attempt 1 keeps a chance of a cheap direct path; from
/// [relayAfterAttempts] + 1 onwards relay is forced, because repeating a
/// failing direct attempt only burns time the operator feels as "dead video".
/// 第 1 次仍给廉价直连一次机会；第 [relayAfterAttempts] + 1 次起强制中继——
/// 重复失败的直连只会白白消耗时间，用户在体感上就是"画面一直黑着"。
RelayMode relayModeForAttempt(int attempt, {int relayAfterAttempts = 2}) {
  if (attempt <= 0) return RelayMode.auto;
  if (attempt <= relayAfterAttempts) return RelayMode.auto;
  return RelayMode.forced;
}

/// Orders and shapes ICE servers for an attempt. / 为一次尝试排序并组装 ICE 服务器。
///
/// Overseas deployments usually run one TURN per region (eu/ap/us). Listing the
/// nearest region first shortens the time to the first usable candidate;
/// forcing relay keeps the media flowing when the direct path is blackholed.
/// 海外部署通常每个区域一套 TURN（eu / ap / us）。把最近区域排在前面可缩短
/// 首个可用候选的产出时间；直连被黑洞时强制中继能让媒体继续流动。
class RelayPlanner {
  const RelayPlanner({
    required this.servers,
    this.preferredRegions = const <String>[],
  });

  /// Configured ICE servers. / 已配置的 ICE 服务器。
  final List<IceServer> servers;

  /// Region tokens matched against the server URL (`eu`, `ap`, `us`, …).
  /// 与服务器 URL 匹配的区域标记（`eu`、`ap`、`us` 等）。
  final List<String> preferredRegions;

  /// Whether at least one TURN server is configured (relay is possible).
  /// 是否至少配置了一台 TURN（具备中继能力）。
  bool get hasTurn => servers.any(isTurnServer);

  /// Servers ordered for [mode]. / 按 [mode] 排序后的服务器。
  List<IceServer> orderFor(RelayMode mode) {
    final turn = servers.where(isTurnServer).toList()..sort(_regionCompare);
    final nonTurn = servers.where((s) => !isTurnServer(s)).toList();
    switch (mode) {
      case RelayMode.direct:
        return <IceServer>[...nonTurn, ...turn];
      case RelayMode.auto:
        return <IceServer>[...turn, ...nonTurn];
      case RelayMode.forced:
        return turn;
    }
  }

  /// Peer-connection configuration for `flutter_webrtc`.
  /// 供 `flutter_webrtc` 使用的 peer connection 配置。
  Map<String, dynamic> configurationFor(
    RelayMode mode, {
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'iceServers': orderFor(mode).map((s) => s.toMap()).toList(),
      'iceTransportPolicy': iceTransportPolicyFor(mode),
      ...extra,
    };
  }

  int _regionCompare(IceServer a, IceServer b) {
    final ai = _regionIndex(a);
    final bi = _regionIndex(b);
    if (ai != bi) return ai.compareTo(bi);
    return 0;
  }

  int _regionIndex(IceServer server) {
    final url = server.urls.toLowerCase();
    for (var i = 0; i < preferredRegions.length; i++) {
      if (url.contains(preferredRegions[i].toLowerCase())) return i;
    }
    return preferredRegions.length;
  }
}

/// Implemented by sessions that can restart ICE in place (network handover).
/// 由支持原地重启 ICE（网络切换）的会话实现。
///
/// WHIP/WHEP (RFC 9725) forbids renegotiation, so the implementation rebuilds
/// the peer connection with a fresh ICE configuration instead of sending a
/// classic `ice-restart` offer.
/// WHIP/WHEP（RFC 9725）禁止重协商，因此实现会用全新的 ICE 配置重建 peer
/// connection，而不是发送经典的 `ice-restart` offer。
abstract class IceRestartable {
  /// Restarts ICE using [mode]; falls back to a full reconnect when the engine
  /// cannot do it in place. / 以 [mode] 重启 ICE；引擎无法原地完成时回退为整链重连。
  Future<void> restartIce({RelayMode mode});
}
