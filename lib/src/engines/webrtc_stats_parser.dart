import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/rtc_stats.dart';

/// Wire name of a track kind in WebRTC stats. / 轨道类型在 WebRTC stats 中的线上述语。
String _kindString(RtcTrackKind kind) {
  switch (kind) {
    case RtcTrackKind.audio:
      return 'audio';
    case RtcTrackKind.video:
    case RtcTrackKind.screen:
      return 'video';
  }
}

/// Finds the first RTP stats report matching [kind] and direction.
/// 查找匹配 [kind] 与方向的第一条 RTP stats 报告。
StatsReport? findRtpReport(
  List<StatsReport> reports,
  RtcTrackKind kind, {
  required bool outbound,
}) {
  final wanted = outbound ? 'outbound-rtp' : 'inbound-rtp';
  for (final report in reports) {
    if (report.type != wanted) continue;
    final mediaKind = report.values['kind'] ?? report.values['mediaType'];
    if (mediaKind is String && mediaKind != _kindString(kind)) continue;
    return report;
  }
  return null;
}

/// Finds the first candidate-pair report (carries RTT). / 查找第一条 candidate-pair 报告（携带 RTT）。
StatsReport? findCandidatePairReport(List<StatsReport> reports) {
  for (final report in reports) {
    if (report.type == 'candidate-pair') return report;
  }
  return null;
}

/// Computes bitrate in kbps from a byte delta over a duration.
/// 由字节增量与时间差计算码率（kbps）。
double computeBitrateKbps(int bytesDelta, Duration duration) {
  final seconds = duration.inMicroseconds / 1000000;
  if (seconds <= 0) return 0;
  return (bytesDelta * 8 / 1000) / seconds;
}

/// Stateful sampler converting raw stats snapshots into [RtcStats].
/// 有状态采样器：把原始 stats 快照转换为 [RtcStats]。
class RtcStatsSampler {
  int _lastBytes = 0;
  DateTime? _lastSampleAt;

  /// Samples one stream's stats. / 采样一路流的 stats。
  RtcStats sample({
    required String streamId,
    required RtcTrackKind kind,
    required List<StatsReport> reports,
    bool outbound = false,
  }) {
    final now = DateTime.now();
    final report = findRtpReport(reports, kind, outbound: outbound);
    var bitrateKbps = 0.0;
    var packetLossPercent = 0.0;
    var jitterMs = 0.0;
    var fps = 0.0;
    var width = 0;
    var height = 0;

    if (report != null) {
      final values = report.values;
      final bytes = _intOf(values[outbound ? 'bytesSent' : 'bytesReceived']);
      if (bytes != null) {
        final last = _lastSampleAt;
        if (last != null) {
          bitrateKbps = computeBitrateKbps(
            bytes - _lastBytes,
            now.difference(last),
          );
        }
        _lastBytes = bytes;
      }
      final lost = _doubleOf(values['packetsLost']) ?? 0;
      final received = _doubleOf(values['packetsReceived']) ?? 0;
      final total = lost + received;
      if (total > 0) {
        packetLossPercent = (lost / total) * 100;
      }
      jitterMs = (_doubleOf(values['jitter']) ?? 0) * 1000;
      fps = _doubleOf(values['framesPerSecond']) ?? 0;
      width = _intOf(values['frameWidth']) ?? 0;
      height = _intOf(values['frameHeight']) ?? 0;
    }
    _lastSampleAt = now;

    final pair = findCandidatePairReport(reports);
    final rttMs = pair == null
        ? 0.0
        : (_doubleOf(pair.values['currentRoundTripTime']) ?? 0) * 1000;

    return RtcStats(
      streamId: streamId,
      kind: kind,
      bitrateKbps: bitrateKbps,
      packetLossPercent: packetLossPercent,
      jitterMs: jitterMs,
      rttMs: rttMs,
      fps: fps,
      width: width,
      height: height,
      actualClarity: ClarityLevel.fromHeight(height),
      timestamp: now,
    );
  }

  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  static double? _doubleOf(Object? value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return null;
  }
}
