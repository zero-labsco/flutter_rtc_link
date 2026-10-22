import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../engines/livekit_subscriber.dart';
import '../subscribers/remote_subscriber.dart';

/// Renders a local or remote video stream, engine-agnostic.
/// 渲染本地或远端视频流，与引擎无关。
///
/// Pass either a [renderer] (WHEP / local preview) or a [subscriber]
/// (LiveKit or WHEP). Consumers never touch engine types.
/// 传入 [renderer]（WHEP / 本地预览）或 [subscriber]（LiveKit / WHEP）即可，
/// 使用方无需接触引擎类型。
class RtcVideoView extends StatelessWidget {
  const RtcVideoView({
    super.key,
    this.renderer,
    this.subscriber,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    this.mirror = false,
    this.placeholderBuilder,
  });

  /// Direct renderer (local camera preview, custom pipelines).
  /// 直接渲染器（本地摄像头预览、自建管线）。
  final VideoRenderer? renderer;

  /// Remote subscriber to render. / 要渲染的远端订阅器。
  final RemoteSubscriber? subscriber;

  /// How the video fits the box. / 视频适配方式。
  final RTCVideoViewObjectFit objectFit;

  /// Mirror horizontally (front camera). / 水平镜像（前置摄像头）。
  final bool mirror;

  /// Placeholder shown before the first frame. / 首帧前的占位组件。
  final WidgetBuilder? placeholderBuilder;

  @override
  Widget build(BuildContext context) {
    final effectiveRenderer = renderer ?? subscriber?.videoRenderer;
    if (effectiveRenderer is RTCVideoRenderer) {
      return RTCVideoView(
        effectiveRenderer,
        objectFit: objectFit,
        mirror: mirror,
        placeholderBuilder: placeholderBuilder,
      );
    }
    final livekit = subscriber;
    if (livekit is LiveKitSubscriber) {
      final track = livekit.videoTrack;
      if (track != null) {
        return lk.VideoTrackRenderer(
          track,
          // LiveKit ships its own fit enum; map the flutter_webrtc one.
          // LiveKit 自带 fit 枚举；此处映射 flutter_webrtc 的枚举。
          fit: objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
              ? lk.VideoViewFit.cover
              : lk.VideoViewFit.contain,
          mirrorMode: mirror
              ? lk.VideoViewMirrorMode.mirror
              : lk.VideoViewMirrorMode.off,
          renderMode: lk.VideoRenderMode.texture,
        );
      }
    }
    final builder = placeholderBuilder;
    if (builder != null) return builder(context);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.videocam_off_outlined)),
    );
  }
}
