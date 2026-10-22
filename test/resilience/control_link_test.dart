import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lan = ControlLinkPath(
    kind: ControlLinkKind.dataChannel,
    id: 'dc-robot-1',
    rttMs: 12,
  );
  const wan = ControlLinkPath(
    kind: ControlLinkKind.mqtt,
    id: 'mqtt-robot-1',
    rttMs: 180,
  );
  const slowWan = ControlLinkPath(
    kind: ControlLinkKind.mqtt,
    id: 'mqtt-far',
    rttMs: 640,
  );

  group('ControlLinkRouter', () {
    test('prefers the peer-to-peer data channel when it is up', () {
      // 数据通道可用时优先点对点数据通道。
      final selection = const ControlLinkRouter().select(<ControlLinkPath>[
        wan,
        lan,
      ]);
      expect(selection!.path.id, 'dc-robot-1');
      expect(selection.reason, ControlLinkSelectionReason.preferredKind);
      expect(selection.withinBudget, isTrue);
    });

    test('falls back to MQTT when the data channel is gone', () {
      // 数据通道不可用时回退到 MQTT。
      final selection = const ControlLinkRouter().select(<ControlLinkPath>[
        const ControlLinkPath(
          kind: ControlLinkKind.dataChannel,
          id: 'dc',
          reachable: false,
        ),
        wan,
      ]);
      expect(selection!.path.id, 'mqtt-robot-1');
      expect(selection.withinBudget, isTrue);
    });

    test('reports a path that misses the latency budget', () {
      // 上报不满足时延预算的路径。
      final selection = const ControlLinkRouter(
        rttBudgetMs: 200,
      ).select(<ControlLinkPath>[slowWan]);
      expect(selection!.withinBudget, isFalse);
      expect(selection.reason, ControlLinkSelectionReason.onlyOption);
    });

    test('returns null when nothing is reachable', () {
      // 无可达路径时返回 null。
      final selection = const ControlLinkRouter().select(<ControlLinkPath>[
        const ControlLinkPath(
          kind: ControlLinkKind.mqtt,
          id: 'dead',
          reachable: false,
        ),
      ]);
      expect(selection, isNull);
    });

    test('prefers an unmetered path when both are equally fast', () {
      // 速度相当时优先不按流量计费的路径。
      final selection = const ControlLinkRouter(preferDataChannel: false)
          .select(<ControlLinkPath>[
            const ControlLinkPath(
              kind: ControlLinkKind.mqtt,
              id: 'metered',
              rttMs: 100,
              metered: true,
            ),
            const ControlLinkPath(
              kind: ControlLinkKind.mqtt,
              id: 'free',
              rttMs: 100,
            ),
          ]);
      expect(selection!.path.id, 'free');
    });
  });

  group('ControlRttTracker', () {
    test('smooths samples and checks the budget', () {
      // 平滑样本并检查预算。
      final tracker = ControlRttTracker(alpha: 0.5, initialRttMs: 100);
      expect(tracker.withinBudget(200), isTrue);
      tracker.sample(300);
      tracker.sample(300);
      expect(tracker.rttMs, greaterThan(200));
      expect(tracker.withinBudget(200), isFalse);
      expect(tracker.samples, 2);
    });
  });

  group('CommandRateLimiter', () {
    test('drops commands inside the minimum interval', () {
      // 丢弃最小间隔内的指令。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final limiter = CommandRateLimiter(
        minInterval: const Duration(milliseconds: 100),
        clock: () => now,
      );
      expect(limiter.allow(), isTrue);
      now = now.add(const Duration(milliseconds: 50));
      expect(limiter.allow(), isFalse);
      now = now.add(const Duration(milliseconds: 60));
      expect(limiter.allow(), isTrue);
      expect(limiter.dropped, 1);
    });

    test('reset clears the window', () {
      // reset 清空窗口。
      final limiter = CommandRateLimiter(
        minInterval: const Duration(minutes: 1),
        clock: () => DateTime(2026, 1, 1, 10, 0, 0),
      );
      expect(limiter.allow(), isTrue);
      expect(limiter.allow(), isFalse);
      limiter.reset();
      expect(limiter.allow(), isTrue);
    });
  });
}
