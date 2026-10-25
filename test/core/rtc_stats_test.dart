import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClarityLevel', () {
    test('fromHeight snaps to the nearest level', () {
      expect(ClarityLevel.fromHeight(null), ClarityLevel.auto);
      expect(ClarityLevel.fromHeight(0), ClarityLevel.auto);
      expect(ClarityLevel.fromHeight(240), ClarityLevel.p360);
      expect(ClarityLevel.fromHeight(360), ClarityLevel.p360);
      expect(ClarityLevel.fromHeight(480), ClarityLevel.p540);
      expect(ClarityLevel.fromHeight(700), ClarityLevel.p720);
      expect(ClarityLevel.fromHeight(1080), ClarityLevel.p1080);
      expect(ClarityLevel.fromHeight(2160), ClarityLevel.p2160);
      expect(ClarityLevel.fromHeight(3840), ClarityLevel.p2160);
    });

    test('VideoQuality is an alias of ClarityLevel', () {
      const VideoQuality quality = VideoQuality.p540;
      expect(quality, isA<ClarityLevel>());
      expect(quality.label, '540p');
    });
  });

  group('connectionQualityFrom', () {
    RtcStats statsWith({
      double rtt = 0,
      double loss = 0,
      double bitrate = 100,
    }) {
      return RtcStats(
        streamId: 's',
        kind: RtcTrackKind.video,
        rttMs: rtt,
        packetLossPercent: loss,
        bitrateKbps: bitrate,
        timestamp: DateTime(2026),
      );
    }

    test('classifies buckets', () {
      expect(
        connectionQualityFrom(statsWith(rtt: 0, bitrate: 0)),
        ConnectionQualityLevel.unknown,
      );
      expect(
        connectionQualityFrom(statsWith(rtt: 500)),
        ConnectionQualityLevel.poor,
      );
      expect(
        connectionQualityFrom(statsWith(rtt: 250)),
        ConnectionQualityLevel.fair,
      );
      expect(
        connectionQualityFrom(statsWith(rtt: 100)),
        ConnectionQualityLevel.good,
      );
      expect(
        connectionQualityFrom(statsWith(rtt: 40)),
        ConnectionQualityLevel.excellent,
      );
    });
  });

  group('RtcStats', () {
    test('serializes to JSON', () {
      final json = RtcStats(
        streamId: 'cam-1',
        kind: RtcTrackKind.video,
        fps: 30,
        width: 1920,
        height: 1080,
        actualClarity: ClarityLevel.p1080,
        timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
      ).toJson();
      expect(json['streamId'], 'cam-1');
      expect(json['kind'], 'video');
      expect(json['width'], 1920);
      expect(json['actualClarity'], '1080p');
      expect(json['timestamp'], '2026-01-02T03:04:05.000Z');
    });
  });
}
