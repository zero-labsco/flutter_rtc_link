import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logging/logging.dart';

import '../core/rtc_events.dart';
import '../core/rtc_stats.dart';
import '../publishers/local_publisher.dart';
import '../publishers/simulcast.dart';
import 'webrtc_stats_parser.dart';
import 'whip_client.dart';
import 'whip_whep_engine.dart';

/// WHIP publisher for the lead operator role.
/// 牵头操作者角色的 WHIP 推流器。
///
/// Two transceivers (audio + video) are created up-front and every later track
/// change is a pure `replaceTrack` — WHIP (RFC 9725) forbids media-section
/// renegotiation after the initial SDP exchange.
/// 音频 + 视频两个 transceiver 预先创建，之后所有轨道变更都是纯
/// `replaceTrack`——WHIP（RFC 9725）禁止初始 SDP 交换后的 media section 重协商。
class WhipWhepPublisher extends LocalPublisher {
  WhipWhepPublisher({required WhipWhepSession session, Logger? logger})
    : _session = session,
      _logger = logger ?? Logger('WhipWhepPublisher'),
      _status = ValueNotifier<PublisherStatus>(const PublisherStatus());

  final WhipWhepSession _session;
  final Logger _logger;
  final ValueNotifier<PublisherStatus> _status;

  RTCPeerConnection? _pc;
  WhipResource? _whipResource;
  MediaStreamTrack? _cameraTrack;
  MediaStream? _cameraStream;
  MediaStreamTrack? _micTrack;
  MediaStreamTrack? _screenTrack;
  RTCRtpSender? _videoSender;
  RTCRtpSender? _audioSender;
  CameraFacing? _currentFacing;
  ClarityLevel _maxClarity = ClarityLevel.p720;
  bool _isScreenSharing = false;
  bool _disposed = false;

  final RtcStatsSampler _videoSampler = RtcStatsSampler();
  final RtcStatsSampler _audioSampler = RtcStatsSampler();

  @override
  ValueNotifier<PublisherStatus> get status => _status;

  @override
  MediaStreamTrack? get cameraTrack => _cameraTrack;

  @override
  MediaStream? get cameraStream => _cameraStream;

  @override
  MediaStreamTrack? get micTrack => _micTrack;

  @override
  MediaStreamTrack? get screenTrack => _screenTrack;

  @override
  Future<void> startCamera({
    CameraFacing facing = CameraFacing.front,
    ClarityLevel maxClarity = ClarityLevel.p720,
  }) async {
    _ensureNotDisposed();
    if (_status.value.cameraActive) {
      if (facing != _currentFacing) await switchCamera(facing);
      return;
    }
    _maxClarity = maxClarity;
    final stream = await _captureVideo(facing, maxClarity);
    _cameraTrack = stream.getVideoTracks().first;
    _cameraStream = stream;
    _currentFacing = facing;
    await _ensurePc();
    if (!_isScreenSharing) {
      await _videoSender?.replaceTrack(_cameraTrack);
    }
    _status.value = _status.value.copyWith(
      cameraActive: true,
      facing: facing,
      publishClarity: maxClarity,
    );
    _session.emit(
      const RtcConnectionStateChanged(state: RtcConnectionState.connected),
    );
  }

  @override
  Future<void> switchCamera(CameraFacing facing) async {
    _ensureNotDisposed();
    if (!_status.value.cameraActive) {
      await startCamera(facing: facing);
      return;
    }
    if (facing == _currentFacing) return;
    // Release the old capture device first: holding it makes getUserMedia for
    // the other camera fail on Android. The visual gap is short and the SDP is
    // untouched (zero renegotiation).
    // 先释放旧采集设备：继续持有会导致 Android 上另一颗摄像头的 getUserMedia
    // 失败。画面短暂中断，但 SDP 完全不动（零重协商）。
    final oldTrack = _cameraTrack;
    _cameraTrack = null;
    await oldTrack?.stop();
    final stream = await _captureVideo(facing, _maxClarity);
    final newTrack = stream.getVideoTracks().first;
    _cameraTrack = newTrack;
    _cameraStream = stream;
    _currentFacing = facing;
    if (!_isScreenSharing) {
      await _videoSender?.replaceTrack(newTrack);
    }
    _status.value = _status.value.copyWith(facing: facing);
  }

  @override
  Future<void> startMic() async {
    _ensureNotDisposed();
    if (_status.value.micActive) return;
    final stream = await mediaDevices.getUserMedia(<String, dynamic>{
      'audio': true,
      'video': false,
    });
    _micTrack = stream.getAudioTracks().first;
    await _ensurePc();
    await _audioSender?.replaceTrack(_micTrack);
    _status.value = _status.value.copyWith(micActive: true);
  }

  @override
  Future<void> startScreenShare() async {
    _ensureNotDisposed();
    if (_status.value.screenActive) return;
    final stream = await mediaDevices.getDisplayMedia(<String, dynamic>{
      'video': true,
      'audio': false,
    });
    _screenTrack = stream.getVideoTracks().first;
    await _ensurePc();
    // Screen replaces the camera track on the SAME sender — the m-line never
    // changes, so no renegotiation is needed.
    // 屏幕在同一个 sender 上替换摄像头轨道——m-line 不变，无需重协商。
    await _videoSender?.replaceTrack(_screenTrack);
    _isScreenSharing = true;
    _status.value = _status.value.copyWith(screenActive: true);
  }

  @override
  Future<void> stopCamera() async {
    final track = _cameraTrack;
    _cameraTrack = null;
    _cameraStream = null;
    if (!_isScreenSharing) {
      await _videoSender?.replaceTrack(null);
    }
    await track?.stop();
    _status.value = _status.value.copyWith(cameraActive: false, facing: null);
  }

  @override
  Future<void> stopMic() async {
    final track = _micTrack;
    _micTrack = null;
    await _audioSender?.replaceTrack(null);
    await track?.stop();
    _status.value = _status.value.copyWith(micActive: false);
  }

  @override
  Future<void> stopScreenShare() async {
    final track = _screenTrack;
    _screenTrack = null;
    _isScreenSharing = false;
    // Restore the camera track on the same sender (still zero renegotiation).
    // 在同一个 sender 上恢复摄像头轨道（依然是零重协商）。
    await _videoSender?.replaceTrack(_cameraTrack);
    await track?.stop();
    _status.value = _status.value.copyWith(screenActive: false);
  }

  @override
  Future<void> setPublishClarity(ClarityLevel level) async {
    _ensureNotDisposed();
    _maxClarity = level;
    _status.value = _status.value.copyWith(publishClarity: level);
    final sender = _videoSender;
    if (sender == null) return;
    final params = sender.parameters;
    applyClarityToEncodings(params.encodings, level);
    await sender.setParameters(params);
    // Cap the capture resolution for fixed levels (IoT power saving).
    // 固定层级时同时限制采集分辨率（IoT 省电）。
    final height = level.height;
    final track = _cameraTrack;
    if (height != null && track != null && !_isScreenSharing) {
      await track.applyConstraints(<String, dynamic>{
        'width': <String, dynamic>{'ideal': height * 16 ~/ 9},
        'height': <String, dynamic>{'ideal': height},
      });
    }
  }

  @override
  Future<void> setMicMuted(bool muted) async {
    _ensureNotDisposed();
    _micTrack?.enabled = !muted;
    _status.value = _status.value.copyWith(micMuted: muted);
  }

  @override
  Future<void> setVideoEnabled(bool enabled) async {
    _ensureNotDisposed();
    final track = _isScreenSharing ? _screenTrack : _cameraTrack;
    track?.enabled = enabled;
    _status.value = _status.value.copyWith(videoEnabled: enabled);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _deleteResource();
    await _cameraTrack?.stop();
    await _micTrack?.stop();
    await _screenTrack?.stop();
    _cameraTrack = null;
    _cameraStream = null;
    _micTrack = null;
    _screenTrack = null;
    await _pc?.close();
    _pc = null;
  }

  /// Republishes an existing (received) track through WHIP — used by
  /// [StreamRelay] for cascade / secondary push. The track is NOT owned by the
  /// publisher and is never stopped here.
  /// 通过 WHIP 转推一条既有（收到的）轨道——供 [StreamRelay] 级联 / 二次推流
  /// 使用。该轨道不归本推流器所有，此处绝不 stop 它。
  Future<void> startRelay({
    required MediaStreamTrack videoTrack,
    MediaStreamTrack? audioTrack,
  }) async {
    _ensureNotDisposed();
    await _ensurePc();
    await _videoSender?.replaceTrack(videoTrack);
    if (audioTrack != null) {
      await _audioSender?.replaceTrack(audioTrack);
    }
    _status.value = _status.value.copyWith(
      cameraActive: true,
      screenActive: false,
      micActive: audioTrack != null,
    );
  }

  /// Samples video stats for the session stats loop. / 为会话 stats 循环采样视频 stats。
  Future<RtcStats?> sampleVideoStats() async {
    final pc = _pc;
    if (pc == null) return null;
    final reports = await pc.getStats();
    return _videoSampler.sample(
      streamId: _session.roomId,
      kind: RtcTrackKind.video,
      reports: reports,
      outbound: true,
    );
  }

  /// Samples audio stats for the session stats loop. / 为会话 stats 循环采样音频 stats。
  Future<RtcStats?> sampleAudioStats() async {
    final pc = _pc;
    if (pc == null) return null;
    final reports = await pc.getStats();
    return _audioSampler.sample(
      streamId: _session.roomId,
      kind: RtcTrackKind.audio,
      reports: reports,
      outbound: true,
    );
  }

  Future<MediaStream> _captureVideo(
    CameraFacing facing,
    ClarityLevel level,
  ) async {
    final constraints = <String, dynamic>{
      'video': <String, dynamic>{
        'facingMode': _facingMode(facing),
        if (level.height != null) ...<String, dynamic>{
          'width': <String, dynamic>{'ideal': level.height! * 16 ~/ 9},
          'height': <String, dynamic>{'ideal': level.height},
        },
      },
      'audio': false,
    };
    try {
      return await mediaDevices.getUserMedia(constraints);
    } catch (e) {
      _session.emitError(e, code: RtcErrorCodes.mediaDeviceFailed);
      rethrow;
    }
  }

  /// Rebuilds the WHIP peer connection with a fresh ICE configuration
  /// (network handover, relay escalation). Existing tracks are re-attached on
  /// the same senders, so the m-lines never change.
  /// 以全新的 ICE 配置重建 WHIP peer connection（网络切换、中继升级）。已有轨道
  /// 重新挂回同一批 sender，m-line 完全不变。
  Future<void> restartIce(Map<String, dynamic> configuration) async {
    _ensureNotDisposed();
    final camera = _cameraTrack;
    final mic = _micTrack;
    final screen = _screenTrack;
    await _deleteResource();
    final old = _pc;
    _pc = null;
    _videoSender = null;
    _audioSender = null;
    if (old != null) {
      old.onIceCandidate = null;
      await old.close();
    }
    await _ensurePc(configuration: configuration);
    // The rebuilt peer connection starts its byte counters from ~0; reset the
    // samplers so the first post-restart sample does not compute a bogus
    // negative bitrate. / 重建的 peer connection 字节计数器从 ~0 开始；重置采样器，
    // 避免重连后的首帧算出虚假负码率。
    _videoSampler.reset();
    _audioSampler.reset();
    await _videoSender?.replaceTrack(_isScreenSharing ? screen : camera);
    await _audioSender?.replaceTrack(mic);
  }

  Future<void> _ensurePc({Map<String, dynamic>? configuration}) async {
    if (_pc != null) return;
    final pc = await createPeerConnection(
      configuration ??
          <String, dynamic>{
            'iceServers': _session.iceServers.map((e) => e.toMap()).toList(),
            'sdpSemantics': 'unified-plan',
            'bundlePolicy': 'max-bundle',
          },
    );
    _pc = pc;
    pc.onIceCandidate = (candidate) async {
      final resource = _whipResource;
      if (resource == null) return;
      await _session.client.sendCandidate(resource, candidate);
    };
    // Pre-create both transceivers so mic/camera starts are pure replaceTrack.
    // 预先创建两个 transceiver，使麦克风 / 摄像头启动都是纯 replaceTrack。
    _videoSender = (await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.SendOnly,
        sendEncodings: buildSimulcastEncodings(_maxClarity),
      ),
    )).sender;
    _audioSender = (await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
    )).sender;
    final offer = await pc.createOffer(<String, dynamic>{});
    await pc.setLocalDescription(offer);
    final result = await _session.client.publish(
      offer.sdp ?? '',
      streamId: _session.roomId,
    );
    _whipResource = result.resource;
    await pc.setRemoteDescription(
      RTCSessionDescription(result.answerSdp, 'answer'),
    );
  }

  Future<void> _deleteResource() async {
    final resource = _whipResource;
    _whipResource = null;
    if (resource == null) return;
    try {
      await _session.client.delete(resource);
    } catch (e) {
      _logger.warning('failed to delete WHIP resource: $e');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Publisher has been disposed.');
    }
  }

  static String _facingMode(CameraFacing facing) {
    switch (facing) {
      case CameraFacing.front:
        return 'user';
      case CameraFacing.rear:
        return 'environment';
      case CameraFacing.external:
        return 'environment';
    }
  }
}
