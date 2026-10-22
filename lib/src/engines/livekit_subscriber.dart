import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../core/rtc_stats.dart';
import '../subscribers/remote_subscriber.dart';

/// LiveKit subscriber wrapping a remote video publication.
/// LiveKit 订阅器：封装一路远端视频 publication。
///
/// Clarity selection uses LiveKit's official per-publication quality API
/// (`RemoteTrackPublication.setVideoQuality`); with `adaptiveStream` enabled
/// the SFU also adjusts the layer automatically.
/// 清晰度选择使用 LiveKit 官方按 publication 的质量 API
/// （`RemoteTrackPublication.setVideoQuality`）；开启 `adaptiveStream` 时
/// SFU 还会自动升降层。
class LiveKitSubscriber extends RemoteSubscriber {
  LiveKitSubscriber({
    required lk.RemoteTrackPublication<lk.RemoteVideoTrack> publication,
    required ClarityLevel quality,
  }) : _publication = publication,
       _clarity = ValueNotifier<ClarityLevel>(quality);

  final lk.RemoteTrackPublication<lk.RemoteVideoTrack> _publication;
  final ValueNotifier<ClarityLevel> _clarity;
  final StreamController<RtcStats> _statsCtrl =
      StreamController<RtcStats>.broadcast();

  @override
  String get streamId => _publication.sid;

  @override
  ValueNotifier<ClarityLevel> get clarity => _clarity;

  @override
  VideoRenderer? get videoRenderer => null;

  /// The remote video track (rendered by `RtcVideoView` through LiveKit's
  /// `VideoTrackRenderer`). / 远端视频轨道（由 `RtcVideoView` 通过 LiveKit 的
  /// `VideoTrackRenderer` 渲染）。
  lk.RemoteVideoTrack? get videoTrack => _publication.track;

  @override
  Stream<RtcStats> get stats => _statsCtrl.stream;

  @override
  Future<void> setClarity(ClarityLevel level) async {
    if (level == _clarity.value) return;
    await _publication.setVideoQuality(_videoQuality(level));
    _clarity.value = level;
  }

  /// Feeds a stats sample routed by the session. / 接收由会话路由的 stats 采样。
  void addStats(RtcStats stats) {
    if (_statsCtrl.isClosed) return;
    _statsCtrl.add(stats);
  }

  @override
  Future<void> dispose() async {
    await _statsCtrl.close();
    _clarity.dispose();
  }

  static lk.VideoQuality _videoQuality(ClarityLevel level) {
    switch (level) {
      case ClarityLevel.auto:
      case ClarityLevel.p1080:
        // auto = "up to high"; adaptiveStream decides the actual layer.
        // auto = "最高到 high"；实际层级由 adaptiveStream 决定。
        return lk.VideoQuality.HIGH;
      case ClarityLevel.p720:
        return lk.VideoQuality.MEDIUM;
      case ClarityLevel.p360:
      case ClarityLevel.p540:
        return lk.VideoQuality.LOW;
    }
  }
}
