import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart';

import '../core/rtc_stats.dart';
import '../publishers/local_publisher.dart';
import 'livekit_engine.dart';

/// LiveKit publisher (room-semantics LocalParticipant wrapper).
/// LiveKit 推流器（房间语义的 LocalParticipant 封装）。
///
/// Track swaps go through LiveKit's own sender `replaceTrack` path, so camera
/// switches and screen share never renegotiate the session.
/// 轨道更换走 LiveKit 自身的 sender `replaceTrack` 路径，摄像头切换与屏幕共享
/// 都不会触发会话重协商。
class LiveKitPublisher extends LocalPublisher {
  LiveKitPublisher({required LiveKitSession session, Logger? logger})
    : _session = session,
      _logger = logger ?? Logger('LiveKitPublisher'),
      _status = ValueNotifier<PublisherStatus>(const PublisherStatus());

  final LiveKitSession _session;
  final Logger _logger;
  final ValueNotifier<PublisherStatus> _status;
  CameraFacing? _currentFacing;
  bool _disposed = false;

  lk.LocalParticipant? get _local => _session.room.localParticipant;

  @override
  ValueNotifier<PublisherStatus> get status => _status;

  @override
  MediaStreamTrack? get cameraTrack =>
      _cameraPublication?.track?.mediaStreamTrack;

  // LiveKit previews its own tracks via lk.VideoTrackRenderer, not a
  // flutter_webrtc MediaStream, so there is no stream to expose here.
  // / LiveKit 通过自身的 lk.VideoTrackRenderer 渲染预览，不走 flutter_webrtc 的
  // MediaStream，因此此处没有可供暴露的流。
  @override
  MediaStream? get cameraStream => null;

  @override
  MediaStreamTrack? get micTrack => _micPublication?.track?.mediaStreamTrack;

  @override
  MediaStreamTrack? get screenTrack =>
      _screenPublication?.track?.mediaStreamTrack;

  lk.LocalTrackPublication<lk.LocalTrack>? _cameraPublication;
  lk.LocalTrackPublication<lk.LocalTrack>? _micPublication;
  lk.LocalTrackPublication<lk.LocalTrack>? _screenPublication;

  @override
  Future<void> startCamera({
    CameraFacing facing = CameraFacing.front,
    ClarityLevel maxClarity = ClarityLevel.p720,
  }) async {
    _ensureNotDisposed();
    // `_local` is null until the room connects, and LiveKit returns null then or
    // when permission is denied — so a real track must be confirmed before the
    // camera is reported active. / `_local` 在房间连上前为 null，此时（或权限被拒
    // 时）LiveKit 返回 null，因此必须在确认真有轨道后才上报相机已开启。
    final publication = await _local?.setCameraEnabled(
      true,
      cameraCaptureOptions: lk.CameraCaptureOptions(
        cameraPosition: _position(facing),
        params: capturePresetFor(maxClarity),
      ),
    );
    if (publication == null) {
      _status.value = _status.value.copyWith(cameraActive: false, facing: null);
      return;
    }
    _cameraPublication = publication;
    _currentFacing = facing;
    _status.value = _status.value.copyWith(
      cameraActive: true,
      facing: facing,
      publishClarity: maxClarity,
    );
  }

  @override
  Future<void> switchCamera(CameraFacing facing) async {
    _ensureNotDisposed();
    if (!_status.value.cameraActive || facing == _currentFacing) {
      if (!_status.value.cameraActive) {
        await startCamera(facing: facing);
      }
      return;
    }
    final track = _cameraPublication?.track;
    if (track is lk.LocalVideoTrack) {
      // LiveKit restarts the capture and replaces it on the same sender.
      // LiveKit 重启采集并在同一个 sender 上替换轨道。
      await track.setCameraPosition(_position(facing));
    }
    _currentFacing = facing;
    _status.value = _status.value.copyWith(facing: facing);
  }

  @override
  Future<void> startMic() async {
    _ensureNotDisposed();
    final publication = await _local?.setMicrophoneEnabled(true);
    if (publication == null) {
      _status.value = _status.value.copyWith(micActive: false);
      return;
    }
    _micPublication = publication;
    _status.value = _status.value.copyWith(micActive: true);
  }

  @override
  Future<void> startScreenShare() async {
    _ensureNotDisposed();
    final publication = await _local?.setScreenShareEnabled(true);
    if (publication == null) {
      _status.value = _status.value.copyWith(screenActive: false);
      return;
    }
    _screenPublication = publication;
    _status.value = _status.value.copyWith(screenActive: true);
  }

  @override
  Future<void> stopCamera() async {
    await _local?.setCameraEnabled(false);
    _cameraPublication = null;
    _currentFacing = null;
    _status.value = _status.value.copyWith(cameraActive: false, facing: null);
  }

  @override
  Future<void> stopMic() async {
    await _local?.setMicrophoneEnabled(false);
    _micPublication = null;
    _status.value = _status.value.copyWith(micActive: false);
  }

  @override
  Future<void> stopScreenShare() async {
    await _local?.setScreenShareEnabled(false);
    _screenPublication = null;
    _status.value = _status.value.copyWith(screenActive: false);
  }

  @override
  Future<void> setPublishClarity(ClarityLevel level) async {
    _ensureNotDisposed();
    _status.value = _status.value.copyWith(publishClarity: level);
    final track = _cameraPublication?.track;
    if (track is! lk.LocalVideoTrack) return;
    // restartTrack replaces the track on the same sender (zero renegotiation).
    // restartTrack 在同一个 sender 上替换轨道（零重协商）。
    await track.restartTrack(
      lk.CameraCaptureOptions(
        cameraPosition: _position(_currentFacing ?? CameraFacing.front),
        params: capturePresetFor(level),
      ),
    );
  }

  @override
  Future<void> setMicMuted(bool muted) async {
    _ensureNotDisposed();
    final publication = _micPublication;
    if (publication == null) return;
    if (muted) {
      await publication.mute(stopOnMute: false);
    } else {
      await publication.unmute(stopOnMute: false);
    }
    _status.value = _status.value.copyWith(micMuted: muted);
  }

  @override
  Future<void> setVideoEnabled(bool enabled) async {
    _ensureNotDisposed();
    final publication = _screenPublication ?? _cameraPublication;
    if (publication == null) return;
    if (enabled) {
      await publication.unmute(stopOnMute: false);
    } else {
      await publication.mute(stopOnMute: false);
    }
    _status.value = _status.value.copyWith(videoEnabled: enabled);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _local?.setCameraEnabled(false);
      await _local?.setMicrophoneEnabled(false);
      await _local?.setScreenShareEnabled(false);
    } catch (e) {
      _logger.warning('failed to disable tracks on dispose: $e');
    }
    _cameraPublication = null;
    _micPublication = null;
    _screenPublication = null;
    // Release the notifier so listeners attached by the UI do not leak after
    // the publisher is gone. / 释放 notifier，避免 UI 注册的监听器在推流器销毁后
    // 泄漏。
    _status.dispose();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Publisher has been disposed.');
    }
  }

  static lk.CameraPosition _position(CameraFacing facing) {
    switch (facing) {
      case CameraFacing.front:
        return lk.CameraPosition.front;
      case CameraFacing.rear:
      case CameraFacing.external:
        return lk.CameraPosition.back;
    }
  }
}
