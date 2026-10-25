import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_rtc_link/src/engines/webrtc_stats_parser.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RtcStatsSampler', () {
    List<StatsReport> report(int bytesSent) => <StatsReport>[
      StatsReport('1', 'outbound-rtp', 0, <String, dynamic>{
        'kind': 'video',
        'bytesSent': bytesSent,
      }),
    ];

    /// A clock that advances by a fixed step on each read, so bitrate math is
    /// deterministic regardless of wall-clock timing.
    /// 每次读取都固定前进一步的时钟，使码率计算与墙钟时序无关、可确定。
    DateTime fixedClock(int Function() tick) =>
        DateTime.fromMicrosecondsSinceEpoch(tick() * 1000000);

    test('treats a counter reset as zero bitrate, then recovers', () {
      // 计数器重置时码率应为 0，随后恢复正常。
      var t = 0;
      final sampler = RtcStatsSampler(clock: () => fixedClock(() => t++));

      // First sample only establishes the baseline (no rate yet).
      // 首帧只建立基线（无码率）。
      final first = sampler.sample(
        streamId: 'cam',
        kind: RtcTrackKind.video,
        reports: report(1000),
        outbound: true,
      );
      expect(first.bitrateKbps, 0);

      // Normal increase over 1s (1000 bytes) → ~8 kbps positive.
      // 正常增长（1 秒内 1000 字节）→ 约 8 kbps 正码率。
      final second = sampler.sample(
        streamId: 'cam',
        kind: RtcTrackKind.video,
        reports: report(2000),
        outbound: true,
      );
      expect(second.bitrateKbps, closeTo(8, 0.001));

      // Counter reset (new peer connection) → must not go negative.
      // 计数器重置（新 peer connection）→ 不得为负。
      final third = sampler.sample(
        streamId: 'cam',
        kind: RtcTrackKind.video,
        reports: report(500),
        outbound: true,
      );
      expect(third.bitrateKbps, 0);

      // After the reset, a normal increase computes correctly again.
      // 重置后正常增长再次正确计算。
      final fourth = sampler.sample(
        streamId: 'cam',
        kind: RtcTrackKind.video,
        reports: report(1500),
        outbound: true,
      );
      expect(fourth.bitrateKbps, closeTo(8, 0.001));
    });

    test('reset() clears the byte baseline', () {
      // reset() 清空字节基线。
      var t = 0;
      final sampler = RtcStatsSampler(clock: () => fixedClock(() => t++));
      sampler.sample(
        streamId: 'cam',
        kind: RtcTrackKind.video,
        reports: report(5000),
        outbound: true,
      );
      sampler.reset();
      final after = sampler.sample(
        streamId: 'cam',
        kind: RtcTrackKind.video,
        reports: report(5000),
        outbound: true,
      );
      expect(after.bitrateKbps, 0);
    });
  });
}
