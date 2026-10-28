import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_rtc_link/flutter_rtc_link_device.dart';
import 'package:flutter_test/flutter_test.dart';

RtcStats stats({String streamId = 'cam-1', double rtt = 40, double loss = 0}) {
  return RtcStats(
    streamId: streamId,
    kind: RtcTrackKind.video,
    rttMs: rtt,
    packetLossPercent: loss,
    bitrateKbps: 1200,
    fps: 30,
    width: 1280,
    height: 720,
    timestamp: DateTime.utc(2026),
  );
}

void main() {
  group('DiagnosticReport', () {
    test('renders JSON and Markdown', () {
      final report = DiagnosticReport(
        generatedAt: DateTime.utc(2026, 1, 1),
        sessionId: 'site-42',
        rtcStats: <RtcStats>[stats()],
        probes: const <NetworkProbeResult>[
          NetworkProbeResult(
            target: NetworkProbeTarget(host: 'turn.example.com', port: 3478),
            reachable: true,
            rttMs: 32,
          ),
        ],
        deviceLogs: const <DeviceLogEntry>[],
        verdict: DiagnosisVerdict.unknown,
        reasons: const <String>['No problem signal detected.'],
      );
      final json = report.toJson();
      expect(json['sessionId'], 'site-42');
      expect(json['verdict'], 'unknown');
      expect((json['probes'] as List).single['reachable'], true);

      final markdown = report.toMarkdown();
      expect(markdown.contains('# RTC Link Diagnostics Report'), isTrue);
      expect(markdown.contains('turn.example.com:3478'), isTrue);
      expect(markdown.contains('cam-1'), isTrue);
    });
  });

  group('Diagnostics classification', () {
    test('unreachable probe classifies as a network problem', () async {
      final report = await Diagnostics.run(
        networkProbe: NetworkProbe(
          targets: const <NetworkProbeTarget>[
            NetworkProbeTarget(host: '203.0.113.1', port: 3478),
          ],
          timeout: const Duration(milliseconds: 300),
        ),
      );
      expect(report.verdict, DiagnosisVerdict.network);
      expect(report.reasons, isNotEmpty);
    });

    test('device-side errors classify as a device problem', () async {
      final collector = DeviceLogCollector();
      await collector.start(deviceId: 'dev');
      collector.log(LogLevel.error, 'firmware', 'cpu overload');
      final report = await Diagnostics.run(deviceLogs: collector);
      expect(report.verdict, DiagnosisVerdict.device);
      await collector.dispose();
    });

    test('no input yields an unknown verdict', () async {
      final report = await Diagnostics.run();
      expect(report.verdict, DiagnosisVerdict.unknown);
      expect(report.reasons.single, contains('No diagnostics input'));
    });
  });
}
