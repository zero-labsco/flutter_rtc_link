import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../core/rtc_events.dart';

/// A WHIP/WHEP server-side resource (the `Location` header of the 201).
/// WHIP/WHEP 服务端资源（201 响应 `Location` 头）。
class WhipResource {
  const WhipResource({
    required this.resourceUrl,
    this.etag,
    this.isPlayback = false,
  });

  /// Absolute URL used for DELETE/PATCH. / 用于 DELETE / PATCH 的绝对 URL。
  final String resourceUrl;

  /// `ETag` header, echoed back in `If-Match`. / `ETag` 头，在 `If-Match` 中原样回传。
  final String? etag;

  /// Whether this resource is a WHEP playback. / 该资源是否为 WHEP 播放。
  final bool isPlayback;
}

/// Result of an SDP negotiation. / SDP 协商结果。
class WhipNegotiationResult {
  const WhipNegotiationResult({
    required this.resource,
    required this.answerSdp,
  });

  /// Server-side resource handle. / 服务端资源句柄。
  final WhipResource resource;

  /// Answer SDP. / 应答 SDP。
  final String answerSdp;
}

/// Minimal WHIP/WHEP client (RFC 9725).
/// 最小 WHIP/WHEP 客户端（RFC 9725）。
///
/// WHIP does **not** support media-section renegotiation after the initial
/// SDP exchange — camera switches must use `replaceTrack`, not new offers.
/// WHIP **不支持**初始 SDP 交换后的 media section 重协商——切换摄像头必须用
/// `replaceTrack`，不能重新 offer。
class WhipWhepClient {
  WhipWhepClient({
    required this.whipUrl,
    required this.whepUrl,
    this.headers = const <String, String>{},
    this.streamQueryParam = 'stream',
    this.timeout = const Duration(seconds: 15),
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// WHIP publish endpoint. / WHIP 推流端点。
  final String whipUrl;

  /// WHEP play endpoint. / WHEP 拉流端点。
  final String whepUrl;

  /// Extra HTTP headers. / 额外 HTTP 头。
  final Map<String, String> headers;

  /// Query parameter carrying the stream id. / 承载流 id 的查询参数名。
  final String streamQueryParam;

  /// Request timeout. / 请求超时。
  final Duration timeout;

  final http.Client _client;

  /// Publishes an offer (WHIP). / 推流 offer（WHIP）。
  Future<WhipNegotiationResult> publish(String sdpOffer, {String? streamId}) =>
      _negotiate(whipUrl, sdpOffer, streamId, isPlayback: false);

  /// Plays an offer (WHEP). / 拉流 offer（WHEP）。
  Future<WhipNegotiationResult> play(String sdpOffer, {String? streamId}) =>
      _negotiate(whepUrl, sdpOffer, streamId, isPlayback: true);

  Future<WhipNegotiationResult> _negotiate(
    String baseUrl,
    String sdpOffer,
    String? streamId, {
    required bool isPlayback,
  }) async {
    final request = http.Request('POST', _endpoint(baseUrl, streamId));
    request.headers['content-type'] = 'application/sdp';
    request.headers.addAll(headers);
    request.body = sdpOffer;
    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: '${isPlayback ? 'WHEP' : 'WHIP'} request to $baseUrl failed.',
        cause: e,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw RtcException(
        code: response.statusCode == 404
            ? RtcErrorCodes.resourceNotFound
            : RtcErrorCodes.signalingFailed,
        message:
            '${isPlayback ? 'WHEP' : 'WHIP'} endpoint returned '
            '${response.statusCode}: ${response.body}',
      );
    }
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message:
            '${isPlayback ? 'WHEP' : 'WHIP'} response is missing the '
            'Location header.',
      );
    }
    return WhipNegotiationResult(
      resource: WhipResource(
        resourceUrl: location,
        etag: response.headers['etag'],
        isPlayback: isPlayback,
      ),
      answerSdp: response.body,
    );
  }

  /// Deletes a resource (ends the session). / 删除资源（结束会话）。
  Future<void> delete(WhipResource resource) async {
    final request = http.Request('DELETE', Uri.parse(resource.resourceUrl));
    final etag = resource.etag;
    if (etag != null && etag.isNotEmpty) {
      request.headers['if-match'] = etag;
    }
    request.headers.addAll(headers);
    try {
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode >= 400) {
        // Deleting an already-gone resource is fine (idempotent teardown).
        // 删除已不存在的资源视为正常（幂等清理）。
        if (response.statusCode != 404) {
          throw RtcException(
            code: RtcErrorCodes.signalingFailed,
            message:
                'DELETE ${resource.resourceUrl} returned '
                '${response.statusCode}.',
          );
        }
      }
    } catch (e) {
      if (e is RtcException) rethrow;
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'DELETE ${resource.resourceUrl} failed.',
        cause: e,
      );
    }
  }

  /// Sends a trickle ICE candidate (PATCH). / 发送 trickle ICE candidate（PATCH）。
  Future<void> sendCandidate(
    WhipResource resource,
    RTCIceCandidate candidate,
  ) async {
    final request = http.Request('PATCH', Uri.parse(resource.resourceUrl));
    request.headers['content-type'] = 'application/trickle-ice-sdp';
    final etag = resource.etag;
    if (etag != null && etag.isNotEmpty) {
      request.headers['if-match'] = etag;
    }
    request.headers.addAll(headers);
    request.body = candidate.candidate ?? '';
    try {
      await _client.send(request).timeout(timeout);
    } catch (e) {
      // Candidate delivery is best-effort; ICE keeps working via the SDP.
      // candidate 投递为尽力而为；ICE 仍可通过 SDP 正常工作。
      return;
    }
  }

  /// Builds the endpoint URL, appending the stream id query parameter.
  /// 构造端点 URL，追加流 id 查询参数。
  ///
  /// WHIP/WHEP servers take the stream id as a query parameter (SRS:
  /// `?app=live&stream=<id>`, ZLMediaKit: `/index/api/whip?stream=<id>`).
  /// An existing `stream` parameter is never overwritten.
  /// WHIP/WHEP 服务器以查询参数接收流 id（SRS：`?app=live&stream=<id>`，
  /// ZLMediaKit：`/index/api/whip?stream=<id>`）。已存在的 `stream` 参数
  /// 不会被覆盖。
  static Uri resolveStreamUri({
    required String endpoint,
    String? streamId,
    String streamQueryParam = 'stream',
  }) {
    final uri = Uri.parse(endpoint);
    if (streamId == null || streamId.isEmpty) return uri;
    final params = Map<String, String>.from(uri.queryParameters);
    params.putIfAbsent(streamQueryParam, () => streamId);
    return uri.replace(queryParameters: params);
  }

  Uri _endpoint(String baseUrl, String? streamId) => resolveStreamUri(
    endpoint: baseUrl,
    streamId: streamId,
    streamQueryParam: streamQueryParam,
  );
}
