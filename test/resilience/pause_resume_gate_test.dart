import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PauseResumeGate', () {
    test('pausing bumps the epoch and invalidates pending operations', () {
      // 暂停会递增 epoch，使待处理操作失效。
      final gate = PauseResumeGate();
      final stamped = gate.stamp();
      expect(stamped, 1);
      expect(gate.accepts(stamped), isTrue);

      gate.pause(PauseReason.background);
      expect(gate.isPaused, isTrue);
      expect(gate.epoch, 2);
      // While suspended the verdict reports the pause itself.
      // 挂起期间，校验结果上报的是"已暂停"。
      expect(gate.verify(stamped), OperationVerdict.paused);
      expect(gate.accepts(stamped), isFalse);
      expect(gate.pauseReason, PauseReason.background);

      // Once resumed, the very same operation is reported as stale forever.
      // 一旦恢复，同一条操作会被永久判定为过期。
      gate.resumeImmediately();
      expect(gate.verify(stamped), OperationVerdict.staleEpoch);
      expect(gate.accepts(stamped), isFalse);
      expect(gate.accepts(gate.stamp()), isTrue);
    });

    test('resume is a two-step handshake on a fresh epoch', () {
      // 恢复是一次两步握手，并落在新的 epoch 上。
      final gate = PauseResumeGate();
      gate.pause(PauseReason.connectionLost);
      final ticket = gate.requestResume();
      expect(ticket.epoch, 3);
      expect(gate.isAwaitingConfirmation, isTrue);
      expect(gate.isActive, isFalse);

      expect(gate.confirmResume(ticket), isTrue);
      expect(gate.isPaused, isFalse);
      expect(gate.epoch, 3);
      // Operations from before the pause must never be accepted again.
      // 暂停之前的操作绝不能被再次接受。
      expect(gate.accepts(1), isFalse);
      expect(gate.accepts(2), isFalse);
      expect(gate.accepts(3), isTrue);
    });

    test('a stale ticket from an earlier cycle is rejected', () {
      // 属于更早周期的票据被拒绝。
      final gate = PauseResumeGate();
      gate.pause(PauseReason.user);
      final first = gate.requestResume();
      final second = gate.requestResume();
      expect(gate.confirmResume(first), isFalse);
      expect(gate.confirmResume(second), isTrue);
    });

    test('an expired ticket is rejected', () {
      // 过期票据被拒绝。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final gate = PauseResumeGate(
        confirmationTimeout: const Duration(seconds: 30),
        clock: () => now,
      );
      gate.pause(PauseReason.background);
      final ticket = gate.requestResume();
      now = now.add(const Duration(seconds: 31));
      expect(ticket.isFreshAt(now), isFalse);
      expect(gate.confirmResume(ticket), isFalse);
      expect(gate.isPaused, isTrue);
      // A fresh ticket still works. / 重新签发的票据仍然有效。
      expect(gate.confirmResume(gate.requestResume()), isTrue);
    });

    test('confirming without a pause fails', () {
      // 未暂停时确认失败。
      final gate = PauseResumeGate();
      gate.pause(PauseReason.user);
      final ticket = gate.requestResume();
      gate.cancelResume();
      expect(gate.confirmResume(ticket), isFalse);
    });

    test('resumeImmediately skips the handshake', () {
      // resumeImmediately 跳过握手。
      final gate = PauseResumeGate();
      gate.pause(PauseReason.networkLost);
      expect(gate.resumeImmediately(afterReconnect: true), isTrue);
      expect(gate.isPaused, isFalse);
      expect(gate.epoch, 2 + 1);
    });

    test('reports discarded operations', () {
      // 上报被丢弃的操作。
      final events = <LinkEvent>[];
      final gate = PauseResumeGate(onEvent: events.add);
      gate.noteDiscarded(count: 3, reason: 'staleEpoch');
      expect(gate.discardedOperations, 3);
      expect(events.whereType<LinkOperationsDiscarded>().single.count, 3);
    });
  });

  group('EpochOperationQueue', () {
    test('delivers an operation created in the current epoch', () {
      // 投递当前 epoch 内创建的操作。
      final gate = PauseResumeGate();
      final queue = EpochOperationQueue<String>(gate);
      expect(queue.submit('forward'), isTrue);
      expect(queue.take(), 'forward');
    });

    test('never replays an operation buffered before a pause', () {
      // 绝不补发暂停前缓存的操作。
      //
      // This is the whole point of the epoch: the joystick position captured
      // while the app was suspended must not move the robot after the resume.
      // 这正是 epoch 的意义：挂起期间采集到的摇杆位置，绝不能在恢复后驱动机器人。
      final gate = PauseResumeGate();
      final dropped = <String>[];
      final queue = EpochOperationQueue<String>(
        gate,
        onDiscard: (op, reason) => dropped.add('$op:$reason'),
      );
      queue.submit('joystick-left');
      gate.pause(PauseReason.background);
      gate.resumeImmediately();
      expect(gate.isPaused, isFalse);
      expect(queue.take(), isNull);
      expect(queue.discarded, 1);
      expect(dropped.single, 'joystick-left:staleEpoch');
      expect(gate.discardedOperations, 1);
    });

    test('refuses new operations while paused', () {
      // 暂停期间拒绝新操作。
      final gate = PauseResumeGate();
      final dropped = <String>[];
      final queue = EpochOperationQueue<String>(
        gate,
        onDiscard: (op, reason) => dropped.add('$op:$reason'),
      );
      gate.pause(PauseReason.connectionLost);
      expect(queue.submit('go'), isFalse);
      expect(queue.pendingCount, 0);
      expect(dropped.single, 'go:paused');
    });

    test('latest wins when the buffer is one deep', () {
      // 缓冲深度为 1 时最新者胜。
      final gate = PauseResumeGate();
      final queue = EpochOperationQueue<String>(gate);
      queue.submit('v1');
      queue.submit('v2');
      expect(queue.pendingCount, 1);
      expect(queue.coalesced, 1);
      expect(queue.take(), 'v2');
    });

    test('drops operations older than maxAge', () {
      // 丢弃超过 maxAge 的操作。
      var now = DateTime(2026, 1, 1, 10, 0, 0);
      final gate = PauseResumeGate();
      final queue = EpochOperationQueue<String>(
        gate,
        maxAge: const Duration(milliseconds: 300),
        clock: () => now,
      );
      queue.submit('cmd');
      now = now.add(const Duration(seconds: 1));
      expect(queue.take(), isNull);
      expect(queue.discarded, 1);
    });
  });
}
