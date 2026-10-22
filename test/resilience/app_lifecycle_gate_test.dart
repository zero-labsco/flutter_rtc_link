import 'package:flutter/widgets.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLifecycleGate.isBackground', () {
    test('only paused, hidden and detached count as background', () {
      // 只有 paused、hidden 与 detached 算作后台。
      expect(AppLifecycleGate.isBackground(AppLifecycleState.resumed), isFalse);
      expect(
        AppLifecycleGate.isBackground(AppLifecycleState.inactive),
        isFalse,
      );
      expect(AppLifecycleGate.isBackground(AppLifecycleState.paused), isTrue);
      expect(AppLifecycleGate.isBackground(AppLifecycleState.hidden), isTrue);
      expect(AppLifecycleGate.isBackground(AppLifecycleState.detached), isTrue);
    });
  });

  group('AppLifecycleGate', () {
    test('forwards only real transitions', () async {
      // 只转发真正的状态跃迁。
      final seen = <bool>[];
      final gate = AppLifecycleGate(
        onBackgroundChanged: (v) async {
          seen.add(v);
        },
      );
      await gate.handle(AppLifecycleState.resumed);
      expect(seen, isEmpty);
      await gate.handle(AppLifecycleState.inactive);
      expect(seen, isEmpty);
      await gate.handle(AppLifecycleState.paused);
      expect(seen, <bool>[true]);
      expect(gate.isBackgrounded, isTrue);
      // Still backgrounded: another background state changes nothing.
      // 仍在后台：再次收到后台状态不产生变化。
      await gate.handle(AppLifecycleState.hidden);
      expect(seen, <bool>[true]);
      await gate.handle(AppLifecycleState.resumed);
      expect(seen, <bool>[true, false]);
      expect(gate.isBackgrounded, isFalse);
    });

    test('drives a pause/resume gate through the app lifecycle', () async {
      // 通过应用生命周期驱动暂停 / 恢复门。
      final gate = PauseResumeGate();
      final lifecycle = AppLifecycleGate(
        onBackgroundChanged: (background) async {
          if (background) {
            gate.pause(PauseReason.background);
          } else {
            gate.requestResume();
          }
        },
      );
      await lifecycle.handle(AppLifecycleState.paused);
      expect(gate.isPaused, isTrue);
      await lifecycle.handle(AppLifecycleState.resumed);
      expect(gate.isAwaitingConfirmation, isTrue);
      expect(gate.confirmResume(gate.pendingTicket!), isTrue);
      expect(gate.isPaused, isFalse);
    });
  });
}
