/// Clarity level: publish-side cap and per-stream subscription quality.
/// 清晰度层级：发布端上限与每路订阅清晰度。
///
/// Publish side: simulcast layers are always encoded; [RtcStats] caps only the
/// top layer (saves power and bandwidth — mandatory on IoT devices).
/// 发布端：始终多层 simulcast 编码；`setPublishClarity` 只限制最高层（省电省流，
/// IoT 设备必配）。
///
/// Subscribe side: each stream selects its own level independently.
/// 订阅端：每路流独立选择，互不影响。
enum ClarityLevel {
  /// Adaptive: let stats (bandwidth/loss/RTT) drive layer selection. / 自适应：由 stats（带宽 / 丢包 / RTT）驱动升降层。
  auto(label: 'auto', height: null, maxBitrateKbps: 0),

  /// 360p. / 360p。
  p360(label: '360p', height: 360, maxBitrateKbps: 450),

  /// 540p. / 540p。
  p540(label: '540p', height: 540, maxBitrateKbps: 800),

  /// 720p. / 720p。
  p720(label: '720p', height: 720, maxBitrateKbps: 1700),

  /// 1080p. / 1080p。
  p1080(label: '1080p', height: 1080, maxBitrateKbps: 3000);

  const ClarityLevel({
    required this.label,
    this.height,
    required this.maxBitrateKbps,
  });

  /// Human-readable label for UI. / 面向 UI 的可读标签。
  final String label;

  /// Target height in pixels, `null` for [auto]. / 目标高度（像素），[auto] 为 `null`。
  final int? height;

  /// Suggested max bitrate in kbps for this layer. / 该层建议的最大码率（kbps）。
  final int maxBitrateKbps;

  /// Returns the closest level for a pixel height. / 返回与像素高度最接近的层级。
  static ClarityLevel fromHeight(int? height) {
    if (height == null || height <= 0) return ClarityLevel.auto;
    if (height <= 360) return ClarityLevel.p360;
    if (height <= 540) return ClarityLevel.p540;
    if (height <= 720) return ClarityLevel.p720;
    return ClarityLevel.p1080;
  }
}

/// [VideoQuality] is an alias of [ClarityLevel] for subscription-side APIs
/// (`quality:` parameters). / [VideoQuality] 是 [ClarityLevel] 的别名，用于订阅侧
/// API（`quality:` 参数）。
typedef VideoQuality = ClarityLevel;

/// Track kind. / 轨道类型。
enum RtcTrackKind {
  /// Microphone track. / 麦克风轨道。
  audio,

  /// Camera track. / 摄像头轨道。
  video,

  /// Screen-share track. / 屏幕共享轨道。
  screen,
}

/// Periodic statistics for one stream. / 单条流的周期性统计。
class RtcStats {
  const RtcStats({
    required this.streamId,
    required this.kind,
    this.bitrateKbps = 0,
    this.packetLossPercent = 0,
    this.jitterMs = 0,
    this.rttMs = 0,
    this.fps = 0,
    this.width = 0,
    this.height = 0,
    this.actualClarity = ClarityLevel.auto,
    required this.timestamp,
  });

  /// Stream (or track) identifier. / 流（或轨道）标识。
  final String streamId;

  /// Track kind this snapshot describes. / 该快照描述的轨道类型。
  final RtcTrackKind kind;

  /// Current bitrate in kbps. / 当前码率（kbps）。
  final double bitrateKbps;

  /// Packet loss percentage (0–100). / 丢包率（0–100）。
  final double packetLossPercent;

  /// Jitter in milliseconds. / 抖动（毫秒）。
  final double jitterMs;

  /// Round-trip time in milliseconds. / 往返时延（毫秒）。
  final double rttMs;

  /// Frames per second (video only). / 帧率（仅视频）。
  final double fps;

  /// Frame width in pixels (video only). / 帧宽（像素，仅视频）。
  final int width;

  /// Frame height in pixels (video only). / 帧高（像素，仅视频）。
  final int height;

  /// Actual clarity currently received (after layer selection). / 当前实际接收的清晰度（升降层后）。
  final ClarityLevel actualClarity;

  /// When this snapshot was taken. / 该快图的采样时间。
  final DateTime timestamp;

  /// Serializes to JSON for diagnostics reports. / 序列化为 JSON 以供诊断报告使用。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'streamId': streamId,
    'kind': kind.name,
    'bitrateKbps': bitrateKbps,
    'packetLossPercent': packetLossPercent,
    'jitterMs': jitterMs,
    'rttMs': rttMs,
    'fps': fps,
    'width': width,
    'height': height,
    'actualClarity': actualClarity.label,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Connection quality bucket derived from [RtcStats]. / 由 [RtcStats] 推导的连接质量档位。
enum ConnectionQualityLevel {
  /// No data yet. / 尚无数据。
  unknown,

  /// Unusable (high loss/RTT). / 不可用（高丢包 / 高 RTT）。
  poor,

  /// Degraded but usable. / 降级但仍可用。
  fair,

  /// Good. / 良好。
  good,

  /// Excellent. / 优秀。
  excellent,
}

/// Maps raw stats to a coarse quality bucket. / 将原始 stats 映射为粗略质量档位。
ConnectionQualityLevel connectionQualityFrom(RtcStats stats) {
  if (stats.rttMs <= 0 && stats.bitrateKbps <= 0) {
    return ConnectionQualityLevel.unknown;
  }
  if (stats.rttMs > 400 || stats.packetLossPercent > 12) {
    return ConnectionQualityLevel.poor;
  }
  if (stats.rttMs > 200 || stats.packetLossPercent > 5) {
    return ConnectionQualityLevel.fair;
  }
  if (stats.rttMs > 90 || stats.packetLossPercent > 1.5) {
    return ConnectionQualityLevel.good;
  }
  return ConnectionQualityLevel.excellent;
}
