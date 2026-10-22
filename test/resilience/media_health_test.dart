import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

RtcStats _stats({
  required double fps,
  double bitrate = 900,
  double loss = 0,
  double jitter = 0,
  double rtt = 60,
  DateTime? at,
}) => RtcStats(
  streamId: 'cam-1',
  kind: RtcTrackKind.video,
  bitrateKbps: bitrate,
  packetLossPercent: loss,
  jitterMs: jitter,
  rttMs: rtt,
  fps: fps,
  width: 1280,
  height: 720,
  timestamp: at ?? DateTime(2026, 1, 1, 10, 0, 0),
);

void main() {
  group('MediaHealthMonitor', () {
    test('detects a frozen picture only after the debounce window', () {
      // 只有在去抖窗口之后才判定画面冻结。
      final monitor = MediaHealthMonitor(
        policy: const WeakNetworkPolicy(
          frozenFps: 2,
          frozenSamples: 2,
          keyframeAfter: Duration(seconds: 4),
          resubscribeAfter: Duration(seconds: 12),
        ),
        clock: () => DateTime(2026, 1, 1, 10, 0, 0),
      );
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final monitor2 = MediaHealthMonitor(
        policy: const WeakNetworkPolicy(
          frozenSamples: 2,
          keyframeAfter: Duration(seconds: 4),
        ),
        clock: () => now,
      );
      // One bad sample is a glitch, not a freeze.
      // 单个坏样本只是毛刺，不是冻结。
      expect(monitor2.feed(_stats(fps: 0)).issue, MediaHealthIssue.healthy);
      now = now.add(const Duration(seconds: 2));
      final frozen = monitor2.feed(_stats(fps: 0));
      expect(frozen.issue, MediaHealthIssue.frozen);
      expect(frozen.action, MediaRecoveryAction.none);
      expect(monitor.feed(_stats(fps: 30)).issue, MediaHealthIssue.healthy);
    });

    test('escalates a freeze to a keyframe and then to a resubscribe', () {
      // 冻结升级为关键帧请求，再升级为重建订阅。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final monitor = MediaHealthMonitor(
        policy: const WeakNetworkPolicy(
          frozenSamples: 1,
          keyframeAfter: Duration(seconds: 4),
          resubscribeAfter: Duration(seconds: 12),
        ),
        clock: () => now,
      );
      expect(monitor.feed(_stats(fps: 0)).issue, MediaHealthIssue.frozen);

      now = now.add(const Duration(seconds: 6));
      expect(
        monitor.feed(_stats(fps: 0)).action,
        MediaRecoveryAction.requestKeyframe,
      );

      now = now.add(const Duration(seconds: 8));
      expect(
        monitor.feed(_stats(fps: 0)).action,
        MediaRecoveryAction.resubscribe,
      );
      expect(monitor.frozenStreamIds, <String>['cam-1']);
    });

    test('congestion downgrades clarity after the degrade window', () {
      // 拥塞在降级窗口之后要求降低清晰度。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final monitor = MediaHealthMonitor(
        policy: const WeakNetworkPolicy(
          frozenSamples: 1,
          congestedRttMs: 400,
          degradeAfter: Duration(seconds: 6),
        ),
        clock: () => now,
      );
      var health = monitor.feed(_stats(fps: 25, rtt: 520));
      expect(health.issue, MediaHealthIssue.congested);
      expect(health.action, MediaRecoveryAction.none);

      now = now.add(const Duration(seconds: 7));
      health = monitor.feed(_stats(fps: 25, rtt: 520));
      expect(health.action, MediaRecoveryAction.downgradeClarity);
    });

    test('recovery needs several good samples', () {
      // 恢复需要多个好样本。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final monitor = MediaHealthMonitor(
        policy: const WeakNetworkPolicy(
          frozenSamples: 1,
          stutterLossPercent: 6,
          recoverySamples: 3,
        ),
        clock: () => now,
      );
      expect(
        monitor.feed(_stats(fps: 25, loss: 8)).issue,
        MediaHealthIssue.stuttering,
      );
      now = now.add(const Duration(seconds: 2));
      expect(monitor.feed(_stats(fps: 30)).issue, MediaHealthIssue.stuttering);
      now = now.add(const Duration(seconds: 2));
      expect(monitor.feed(_stats(fps: 30)).issue, MediaHealthIssue.stuttering);
      now = now.add(const Duration(seconds: 2));
      expect(monitor.feed(_stats(fps: 30)).issue, MediaHealthIssue.healthy);
    });

    test('a stream that has not started yet is not frozen', () {
      // 尚未开始的流不算冻结。
      final monitor = MediaHealthMonitor(
        clock: () => DateTime(2026, 1, 1, 10, 0, 0),
      );
      final health = monitor.feed(_stats(fps: 0, bitrate: 0, rtt: 0));
      expect(health.issue, MediaHealthIssue.healthy);
    });

    test('emits only on change', () async {
      // 仅在变化时投递。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final monitor = MediaHealthMonitor(
        policy: const WeakNetworkPolicy(frozenSamples: 1),
        clock: () => now,
      );
      final seen = <MediaHealth>[];
      final sub = monitor.changes.listen(seen.add);
      monitor.feed(_stats(fps: 30));
      monitor.feed(_stats(fps: 30));
      now = now.add(const Duration(seconds: 2));
      monitor.feed(_stats(fps: 0));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(seen.length, 2);
      expect(seen.last.issue, MediaHealthIssue.frozen);
      await sub.cancel();
      monitor.dispose();
    });
  });

  group('degradeClarity', () {
    test('steps down but never below the floor', () {
      // 逐档下调，且不低于下限。
      const policy = WeakNetworkPolicy(minClarity: ClarityLevel.p360);
      expect(
        degradeClarity(ClarityLevel.p1080, policy: policy),
        ClarityLevel.p720,
      );
      expect(
        degradeClarity(ClarityLevel.p720, policy: policy),
        ClarityLevel.p540,
      );
      expect(
        degradeClarity(ClarityLevel.p540, policy: policy),
        ClarityLevel.p360,
      );
      expect(
        degradeClarity(ClarityLevel.p360, policy: policy),
        ClarityLevel.p360,
      );
    });

    test('auto starts below the top layer', () {
      // auto 从低于最高层开始。
      expect(degradeClarity(ClarityLevel.auto), ClarityLevel.p360);
    });
  });
}
