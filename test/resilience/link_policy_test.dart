import 'dart:math' as math;

import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReconnectPolicy', () {
    test('backoff doubles and is capped by maxDelay', () {
      // 退避按 2 倍增长，并被 maxDelay 截断。
      const policy = ReconnectPolicy(
        baseDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 4),
      );
      expect(policy.delayForAttempt(1), const Duration(milliseconds: 500));
      expect(policy.delayForAttempt(2), const Duration(seconds: 1));
      expect(policy.delayForAttempt(3), const Duration(seconds: 2));
      expect(policy.delayForAttempt(4), const Duration(seconds: 4));
      expect(policy.delayForAttempt(9), const Duration(seconds: 4));
    });

    test('attempt budget is enforced', () {
      // 尝试预算被强制执行。
      const policy = ReconnectPolicy(maxAttempts: 3);
      expect(policy.allowsAttempt(3), isTrue);
      expect(policy.allowsAttempt(4), isFalse);
    });
  });

  group('ReconnectSupervisor', () {
    test('schedules attempts with jitter and escalates to relay', () {
      // 带抖动地安排尝试，并升级到中继。
      final supervisor = ReconnectSupervisor(
        policy: const ReconnectPolicy(
          baseDelay: Duration(milliseconds: 100),
          maxDelay: Duration(seconds: 1),
          jitterRatio: 0,
          relayAfterAttempts: 1,
        ),
      );
      expect(supervisor.attempt, 0);
      expect(supervisor.scheduleNext(), const Duration(milliseconds: 100));
      expect(supervisor.attempt, 1);
      expect(supervisor.currentRelayMode, RelayMode.auto);
      supervisor.recordFailure();
      expect(supervisor.scheduleNext(), const Duration(milliseconds: 200));
      expect(supervisor.currentRelayMode, RelayMode.forced);
    });

    test('gives up when the budget is exhausted', () {
      // 预算耗尽后放弃重连。
      final supervisor = ReconnectSupervisor(
        policy: const ReconnectPolicy(maxAttempts: 2, jitterRatio: 0),
      );
      expect(supervisor.scheduleNext(), isNotNull);
      supervisor.recordFailure();
      expect(supervisor.scheduleNext(), isNotNull);
      supervisor.recordFailure();
      expect(supervisor.exhausted, isTrue);
      expect(supervisor.scheduleNext(), isNull);
    });

    test('a flapping link never resets the attempt counter', () {
      // 抖动链路永不重置尝试计数。
      final supervisor = ReconnectSupervisor(
        policy: const ReconnectPolicy(
          maxAttempts: 3,
          jitterRatio: 0,
          stableWindow: Duration(minutes: 1),
        ),
      );
      supervisor.scheduleNext();
      supervisor.recordSuccess();
      // Fails again 2 s later: far below the stable window.
      // 2 秒后再次失败：远低于稳定窗口。
      supervisor.recordFailure(
        at: DateTime.now().add(const Duration(seconds: 2)),
      );
      expect(supervisor.attempt, 1);
      final next = supervisor.scheduleNext();
      expect(next, isNotNull);
      expect(supervisor.attempt, 2);
    });

    test('a stable link resets the counter on the next failure', () {
      // 稳定链路在下一次失败时重置计数。
      final supervisor = ReconnectSupervisor(
        policy: const ReconnectPolicy(
          jitterRatio: 0,
          stableWindow: Duration(seconds: 10),
        ),
      );
      supervisor.scheduleNext();
      supervisor.scheduleNext();
      expect(supervisor.attempt, 2);
      supervisor.recordSuccess(at: DateTime(2026, 1, 1, 10, 0, 0));
      supervisor.recordFailure(at: DateTime(2026, 1, 1, 10, 1, 0));
      expect(supervisor.attempt, 0);
    });

    test('jitter stays inside the configured ratio', () {
      // 抖动保持在配置比例范围内。
      final supervisor = ReconnectSupervisor(
        policy: const ReconnectPolicy(
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 1),
          jitterRatio: 0.5,
        ),
        random: _SeqRandom(),
      );
      for (var i = 0; i < 5; i++) {
        final delay = supervisor.scheduleNext();
        expect(delay!.inMilliseconds, greaterThanOrEqualTo(500));
        expect(delay.inMilliseconds, lessThanOrEqualTo(1500));
      }
    });
  });
}

/// Deterministic random: 0, 1, 0, 1 … / 确定性随机：0、1、0、1……
class _SeqRandom implements math.Random {
  int _n = 0;

  @override
  bool nextBool() => (_n++ % 2) == 0;

  @override
  double nextDouble() => (_n++ % 2) == 0 ? 0.0 : 1.0;

  @override
  int nextInt(int max) => _n++ % max;
}
