import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/rtc_stats.dart';

/// Camera facing (and generic capture source). / 摄像头朝向（及通用采集源）。
enum CameraFacing {
  /// Front (user-facing) camera. / 前置（面向用户）摄像头。
  front,

  /// Rear (world-facing) camera. / 后置（面向环境）摄像头。
  rear,

  /// External camera (UVC / capture card). / 外接摄像头（UVC / 采集卡）。
  external,
}

/// Publisher status snapshot. / 推流器状态快照。
class PublisherStatus {
  const PublisherStatus({
    this.cameraActive = false,
    this.micActive = false,
    this.screenActive = false,
    this.micMuted = false,
    this.videoEnabled = true,
    this.publishClarity = ClarityLevel.p720,
    this.facing,
  });

  /// Whether the camera track is live. / 摄像头轨道是否在采集中。
  final bool cameraActive;

  /// Whether the microphone track is live. / 麦克风轨道是否在采集中。
  final bool micActive;

  /// Whether screen share is live. / 屏幕共享是否进行中。
  final bool screenActive;

  /// Whether the microphone is muted (track kept, silent). / 麦克风是否静音（保留轨道但不发声）。
  final bool micMuted;

  /// Whether video is enabled (track kept, black frames). / 视频是否开启（保留轨道但出黑帧）。
  final bool videoEnabled;

  /// Current publish clarity cap. / 当前发布清晰度上限。
  final ClarityLevel publishClarity;

  /// Current camera facing. / 当前摄像头朝向。
  final CameraFacing? facing;

  /// Copies with the given fields replaced. / 复制并替换给定字段。
  PublisherStatus copyWith({
    bool? cameraActive,
    bool? micActive,
    bool? screenActive,
    bool? micMuted,
    bool? videoEnabled,
    ClarityLevel? publishClarity,
    CameraFacing? facing,
  }) {
    return PublisherStatus(
      cameraActive: cameraActive ?? this.cameraActive,
      micActive: micActive ?? this.micActive,
      screenActive: screenActive ?? this.screenActive,
      micMuted: micMuted ?? this.micMuted,
      videoEnabled: videoEnabled ?? this.videoEnabled,
      publishClarity: publishClarity ?? this.publishClarity,
      facing: facing ?? this.facing,
    );
  }
}

/// Local publisher for the lead operator role.
/// 牵头操作者角色的本地推流器。
///
/// Key contracts:
/// - [switchCamera] replaces the capture track via `RTCRtpSender.replaceTrack`
///   with **zero renegotiation** (WHIP forbids media-section changes after the
///   initial SDP exchange, RFC 9725).
/// - [setPublishClarity] only caps the top simulcast layer; lower layers stay
///   available to subscribers.
///
/// 关键约定：
/// - [switchCamera] 通过 `RTCRtpSender.replaceTrack` 换轨，**零重协商**
///   （RFC 9725 明确 WHIP 不支持初始 SDP 交换后的 media section 变更）；
/// - [setPublishClarity] 只限制 simulcast 最高层，低层仍可供订阅端选择。
abstract class LocalPublisher {
  /// Live status. / 实时状态。
  ValueNotifier<PublisherStatus> get status;

  /// Whether the camera is live. / 摄像头是否在采集中。
  bool get isCameraActive => status.value.cameraActive;

  /// Whether the microphone is live. / 麦克风是否在采集中。
  bool get isMicActive => status.value.micActive;

  /// Whether screen share is live. / 屏幕共享是否进行中。
  bool get isScreenActive => status.value.screenActive;

  /// Starts the camera with simulcast layers. / 以 simulcast 分层启动摄像头。
  Future<void> startCamera({
    CameraFacing facing = CameraFacing.front,
    ClarityLevel maxClarity = ClarityLevel.p720,
  });

  /// Switches the capture source without renegotiation. / 在不重协商的情况下切换采集源。
  Future<void> switchCamera(CameraFacing facing);

  /// Starts the microphone. / 启动麦克风。
  Future<void> startMic();

  /// Starts screen share (replaces the camera track on the video sender). / 开始屏幕共享（在视频 sender 上替换摄像头轨道）。
  Future<void> startScreenShare();

  /// Stops the camera. / 停止摄像头。
  Future<void> stopCamera();

  /// Stops the microphone. / 停止麦克风。
  Future<void> stopMic();

  /// Stops screen share (restores the camera track if active). / 停止屏幕共享（如摄像头在采集中则恢复）。
  Future<void> stopScreenShare();

  /// Caps the publish clarity (top simulcast layer). / 限制发布清晰度（simulcast 最高层）。
  Future<void> setPublishClarity(ClarityLevel level);

  /// Mutes/unmutes the microphone without stopping capture. / 静音 / 取消静音麦克风（不停止采集）。
  Future<void> setMicMuted(bool muted);

  /// Enables/disables video without stopping capture. / 开启 / 关闭视频（不停止采集）。
  Future<void> setVideoEnabled(bool enabled);

  /// Camera track, if live. / 摄像头轨道（采集中）。
  MediaStreamTrack? get cameraTrack;

  /// Microphone track, if live. / 麦克风轨道（采集中）。
  MediaStreamTrack? get micTrack;

  /// Screen track, if live. / 屏幕轨道（共享中）。
  MediaStreamTrack? get screenTrack;

  /// Disposes the publisher and all tracks. / 释放推流器及所有轨道。
  Future<void> dispose();
}
