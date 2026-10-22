import 'package:flutter/material.dart';

import '../core/rtc_stats.dart';
import '../publishers/local_publisher.dart';

/// Control bar bound to a [LocalPublisher]: mic, camera, facing switch,
/// screen share, clarity and leave. / 绑定到 [LocalPublisher] 的控制条：
/// 麦克风、摄像头、镜头切换、屏幕共享、清晰度与离开。
///
/// All colors come from the ambient theme. / 所有颜色取自当前主题。
class RtcControlBar extends StatelessWidget {
  const RtcControlBar({
    super.key,
    required this.publisher,
    this.onLeave,
    this.showClaritySelector = true,
    this.showScreenShare = true,
  });

  /// Publisher to control. / 被控制的推流器。
  final LocalPublisher publisher;

  /// Leave callback. / 离开回调。
  final VoidCallback? onLeave;

  /// Whether the clarity selector is shown. / 是否显示清晰度选择器。
  final bool showClaritySelector;

  /// Whether the screen-share button is shown. / 是否显示屏幕共享按钮。
  final bool showScreenShare;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PublisherStatus>(
      valueListenable: publisher.status,
      builder: (context, status, _) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            IconButton.outlined(
              tooltip: status.micMuted
                  ? 'Unmute microphone'
                  : 'Mute microphone',
              icon: Icon(status.micMuted ? Icons.mic_off : Icons.mic),
              onPressed: status.micActive
                  ? () => publisher.setMicMuted(!status.micMuted)
                  : null,
            ),
            IconButton.outlined(
              tooltip: status.cameraActive ? 'Stop camera' : 'Start camera',
              icon: Icon(
                status.cameraActive ? Icons.videocam : Icons.videocam_off,
              ),
              onPressed: status.cameraActive
                  ? () => publisher.stopCamera()
                  : () => publisher.startCamera(),
            ),
            IconButton.outlined(
              tooltip: 'Switch camera',
              icon: const Icon(Icons.cameraswitch),
              onPressed: status.cameraActive
                  ? () => publisher.switchCamera(_nextFacing(status.facing))
                  : null,
            ),
            if (showScreenShare)
              IconButton.outlined(
                tooltip: status.screenActive
                    ? 'Stop screen share'
                    : 'Start screen share',
                icon: Icon(
                  status.screenActive
                      ? Icons.stop_screen_share
                      : Icons.screen_share,
                ),
                onPressed: status.screenActive
                    ? () => publisher.stopScreenShare()
                    : () => publisher.startScreenShare(),
              ),
            if (showClaritySelector)
              PopupMenuButton<ClarityLevel>(
                tooltip: 'Publish clarity',
                initialValue: status.publishClarity,
                icon: const Icon(Icons.high_quality),
                onSelected: publisher.setPublishClarity,
                itemBuilder: (context) => const <PopupMenuEntry<ClarityLevel>>[
                  PopupMenuItem<ClarityLevel>(
                    value: ClarityLevel.auto,
                    child: Text('Auto'),
                  ),
                  PopupMenuItem<ClarityLevel>(
                    value: ClarityLevel.p360,
                    child: Text('360p'),
                  ),
                  PopupMenuItem<ClarityLevel>(
                    value: ClarityLevel.p540,
                    child: Text('540p'),
                  ),
                  PopupMenuItem<ClarityLevel>(
                    value: ClarityLevel.p720,
                    child: Text('720p'),
                  ),
                  PopupMenuItem<ClarityLevel>(
                    value: ClarityLevel.p1080,
                    child: Text('1080p'),
                  ),
                ],
              ),
            if (onLeave != null)
              FilledButton.icon(
                onPressed: onLeave,
                icon: const Icon(Icons.call_end),
                label: const Text('Leave'),
              ),
          ],
        );
      },
    );
  }

  static CameraFacing _nextFacing(CameraFacing? current) {
    switch (current) {
      case CameraFacing.front:
        return CameraFacing.rear;
      case CameraFacing.rear:
      case CameraFacing.external:
      case null:
        return CameraFacing.front;
    }
  }
}
