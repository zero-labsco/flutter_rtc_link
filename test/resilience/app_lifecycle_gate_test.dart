import 'package:flutter/widgets.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a rapid background→foreground toggle ends in the foreground', () async {
    // 快速的"后台→前台"切换必须以"前台"结束，不能把已回前台的链路错误拆除。
    final seen = <bool>[];
    final gate = AppLifecycleGate(
      onBackgroundChanged: (background) async => seen.add(background),
    );
    final toBackground = gate.handle(AppLifecycleState.paused);
    final toForeground = gate.handle(AppLifecycleState.resumed);
    await Future.wait(<Future<void>>[toBackground, toForeground]);
    expect(gate.isBackgrounded, isFalse);
    expect(seen, isNotEmpty);
    expect(seen.last, isFalse);
  });
}
