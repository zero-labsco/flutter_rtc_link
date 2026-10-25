import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

import '../core/rtc_events.dart';
import '../core/rtc_stats.dart';
import '../subscribers/remote_subscriber.dart';
import 'webrtc_stats_parser.dart';
import 'whip_client.dart';
import 'whip_whep_engine.dart';

/// WHEP subscriber for one remote stream. / 一路远端流的 WHEP 订阅器。
///
/// Clarity switching on a single-layer WHEP stream is not a soft switch: the
/// subscriber re-points to a variant stream id (`<stream>_sd` / `_hd` / `_fhd`,
/// the IoT camera main/sub-stream convention), which costs 1–2 s of black
/// frames. Simulcast streams with SDP rid layers switch without any gap on the
/// server side.
/// 单层 WHEP 流的清晰度切换不是软切换：订阅器改指向变体流 id
/// （`<stream>_sd` / `_hd` / `_fhd`，IoT 摄像头主 / 子码流惯例），有 1~2s 黑帧。
/// 带 SDP rid 分层的 simulcast 流由服务端选层，无任何闪断。
class WhepSubscriber extends RemoteSubscriber {
  WhepSubscriber({
    required WhipWhepSession session,
    required String streamId,
    String? resourceStreamId,
    required ClarityLevel quality,
    Logger? logger,
  }) : _session = session,
       _streamId = streamId,
       _resourceStreamId = resourceStreamId ?? streamId,
       _clarity = ValueNotifier<ClarityLevel>(quality),
       _logger = logger ?? Logger('WhepSubscriber');

  final WhipWhepSession _session;
  final String _streamId;
  final Logger _logger;
  final ValueNotifier<ClarityLevel> _clarity;
  final StreamController<RtcStats> _statsCtrl =
      StreamController<RtcStats>.broadcast();
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  final RtcStatsSampler _sampler = RtcStatsSampler();

  final String _resourceStreamId;
  RTCPeerConnection? _pc;
  WhipResource? _whepResource;
  bool _disposed = false;

  @override
  String get streamId => _streamId;

  /// The stream id actually being played (may be a clarity variant). / 实际播放的流 id（可能是清晰度变体）。
  String get resourceStreamId => _resourceStreamId;

  /// The received video track (relay / cascade use). / 收到的视频轨道（级联 / 转接使用）。
  MediaStreamTrack? get receivedVideoTrack => _videoTrack;

  MediaStreamTrack? _videoTrack;

  @override
  ValueNotifier<ClarityLevel> get clarity => _clarity;

  @override
  VideoRenderer? get videoRenderer => _renderer;

  @override
  Stream<RtcStats> get stats => _statsCtrl.stream;

  /// Default ICE configuration for this session. / 本会话的默认 ICE 配置。
  Map<String, dynamic> defaultIceConfiguration() => <String, dynamic>{
    'iceServers': _session.iceServers.map((e) => e.toMap()).toList(),
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
  };

  /// Starts WHEP playback. / 开始 WHEP 播放。
  Future<void> start({Map<String, dynamic>? iceConfiguration}) async {
    await _renderer.initialize();
    await _startPc(iceConfiguration ?? defaultIceConfiguration());
  }

  /// Rebuilds the peer connection (network handover / frozen stream recovery).
  /// 重建 peer connection（网络切换 / 冻结流恢复）。
  ///
  /// WHIP/WHEP (RFC 9725) has no in-place ICE restart, so the only legal
  /// recovery is to delete the resource and play again with fresh ICE.
  /// WHIP/WHEP（RFC 9725）不支持原地 ICE 重启，唯一合规的恢复方式是删除资源
  /// 后用全新的 ICE 重新拉流。
  Future<void> restart({Map<String, dynamic>? iceConfiguration}) async {
    await _teardownPc();
    await _startPc(iceConfiguration ?? defaultIceConfiguration());
  }

  /// Candidates gathered before the WHEP resource existed. /
  /// WHEP 资源存在之前收集到的候选。
  final List<RTCIceCandidate> _pendingCandidates = <RTCIceCandidate>[];

  Future<void> _startPc(Map<String, dynamic> configuration) async {
    final pc = await createPeerConnection(configuration);
    _pc = pc;
    pc.onIceCandidate = (candidate) async {
      final resource = _whepResource;
      if (resource == null) {
        // Buffer it: the resource only exists once the WHEP POST returns, and
        // dropping these meant trickle-only servers never connected. /
        // 缓存起来：资源要等 WHEP POST 返回才存在，丢弃这些候选会让仅支持
        // trickle 的服务端永远连不上。
        _pendingCandidates.add(candidate);
        return;
      }
      await _session.client.sendCandidate(resource, candidate);
    };
    pc.onTrack = (event) {
      if (event.track.kind == 'video') {
        _videoTrack = event.track;
        _renderer.setSrcObject(
          stream: event.streams.isNotEmpty ? event.streams.first : null,
          trackId: event.track.id,
        );
      }
    };
    // Receive-only transceivers: no upload, no renegotiation later.
    // 只收 transceiver：无上传、之后无重协商。
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    final offer = await pc.createOffer(<String, dynamic>{});
    await pc.setLocalDescription(offer);
    final result = await _session.client.play(
      offer.sdp ?? '',
      streamId: _resourceStreamId,
    );
    _whepResource = result.resource;
    await _flushPendingCandidates();
    await pc.setRemoteDescription(
      RTCSessionDescription(result.answerSdp, 'answer'),
    );
  }

  /// Re-sends candidates gathered before the resource existed. /
  /// 重新发送资源存在之前收集到的候选。
  Future<void> _flushPendingCandidates() async {
    final resource = _whepResource;
    if (resource == null) return;
    final pending = _pendingCandidates.toList();
    _pendingCandidates.clear();
    for (final candidate in pending) {
      await _session.client.sendCandidate(resource, candidate);
    }
  }

  /// Closes the peer connection and deletes the server-side WHEP resource
  /// without touching the renderer or the streams (so [restart] can reuse
  /// them). / 关闭 peer connection 并删除服务端 WHEP 资源，但不动 renderer 与
  /// 事件流（以便 [restart] 复用它们）。
  Future<void> _teardownPc() async {
    final resource = _whepResource;
    _whepResource = null;
    if (resource != null) {
      try {
        await _session.client.delete(resource);
      } catch (e) {
        _logger.fine('failed to delete WHEP resource during restart: $e');
      }
    }
    final pc = _pc;
    _pc = null;
    _videoTrack = null;
    if (pc != null) {
      pc.onIceCandidate = null;
      pc.onTrack = null;
      await pc.close();
    }
  }

  @override
  Future<void> setClarity(ClarityLevel level) async {
    if (level == _clarity.value) return;
    if (level == ClarityLevel.auto) {
      // Auto means "whatever the server/SFU decides"; no action needed here.
      // auto 表示"服务端 / SFU 自行决定"，无需动作。
      _clarity.value = ClarityLevel.auto;
      return;
    }
    for (final candidate in _variantCandidates(level)) {
      if (candidate == _resourceStreamId) {
        _clarity.value = level;
        return;
      }
      final switched = await _session.switchToVariantStream(
        this,
        candidate,
        level,
      );
      if (switched) {
        // The engine replaced this object: the live subscriber is registered
        // under the same stream id and already carries `level`, while `this`
        // is disposed. Never touch a disposed notifier. /
        // 引擎替换了本对象：存活的订阅器登记在同一 stream id 下且已带有 `level`，
        // 而 `this` 已被销毁。绝不操作已销毁的 notifier。
        return;
      }
    }
    // No variant published: stay on auto and report a recoverable error so the
    // UI can tell the user this stream has no manual clarity options.
    // 没有发布变体：保持 auto 并上报可恢复错误，让 UI 能提示该流无手动清晰度选项。
    _session.emit(
      RtcError(
        error: RtcException(
          code: RtcErrorCodes.unsupported,
          message:
              'Stream $_resourceStreamId publishes no variant for '
              '${level.label}; staying on auto.',
        ),
      ),
    );
  }

  /// Samples video stats for the session stats loop. / 为会话 stats 循环采样视频 stats。
  Future<RtcStats?> sampleVideoStats() async {
    final pc = _pc;
    if (pc == null) return null;
    final reports = await pc.getStats();
    final stats = _sampler.sample(
      streamId: _streamId,
      kind: RtcTrackKind.video,
      reports: reports,
      outbound: false,
    );
    if (!_statsCtrl.isClosed) _statsCtrl.add(stats);
    return stats;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final resource = _whepResource;
    _whepResource = null;
    if (resource != null) {
      try {
        await _session.client.delete(resource);
      } catch (e) {
        _logger.warning('failed to delete WHEP resource: $e');
      }
    }
    try {
      await _renderer.dispose();
    } catch (e) {
      _logger.fine('renderer dispose failed: $e');
    }
    await _pc?.close();
    _pc = null;
    await _statsCtrl.close();
    _clarity.dispose();
  }

  List<String> _variantCandidates(ClarityLevel level) {
    final suffixes = <String>[];
    switch (level) {
      case ClarityLevel.auto:
        break;
      case ClarityLevel.p360:
      case ClarityLevel.p540:
        suffixes.add('sd');
      case ClarityLevel.p720:
        suffixes.add('hd');
      case ClarityLevel.p1080:
      case ClarityLevel.p2160:
        suffixes.addAll(<String>['fhd', 'hd']);
    }
    return suffixes
        .expand(
          (suffix) => <String>[
            '${_resourceStreamId}_$suffix',
            '${_streamId}_$suffix',
          ],
        )
        .toList();
  }
}
