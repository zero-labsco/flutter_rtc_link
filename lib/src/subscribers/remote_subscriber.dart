import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/rtc_stats.dart';

/// Remote subscriber for one stream. / 一路远端流的订阅器。
///
/// Clarity selection is per-stream and independent: switching one subscriber
/// never consumes upload bandwidth and never affects other subscribers.
/// 清晰度选择按路独立：切换某一路订阅不消耗上传带宽，也不影响其他订阅者。
abstract class RemoteSubscriber {
  /// Stream id. / 流 id。
  String get streamId;

  /// Current clarity selection. / 当前清晰度选择。
  ValueNotifier<ClarityLevel> get clarity;

  /// Video renderer for engines backed by `flutter_webrtc` (WHEP).
  /// 基于 `flutter_webrtc`（WHEP）的引擎所使用的视频渲染器。
  VideoRenderer? get videoRenderer;

  /// Periodic stats for this stream. / 该流的周期性 stats。
  Stream<RtcStats> get stats;

  /// Selects clarity for this stream only. / 仅为该路选择清晰度。
  Future<void> setClarity(ClarityLevel level);

  /// Disposes the subscriber. / 释放订阅器。
  Future<void> dispose();
}
