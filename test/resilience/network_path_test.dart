import 'dart:async';

import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final wifi = NetworkPath(
    kind: NetworkKind.wifi,
    generation: 1,
    label: 'shop-2.4G',
    since: DateTime(2026, 1, 1),
  );
  final cellular = NetworkPath(
    kind: NetworkKind.cellular,
    metered: true,
    generation: 2,
    since: DateTime(2026, 1, 1, 0, 1),
  );
  final wifiRoamed = NetworkPath(
    kind: NetworkKind.wifi,
    generation: 3,
    label: 'shop-5G',
    since: DateTime(2026, 1, 1, 0, 2),
  );
  final offline = NetworkPath(
    kind: NetworkKind.none,
    generation: 4,
    since: DateTime(2026, 1, 1, 0, 3),
  );

  group('NetworkPath', () {
    test('only none is unusable', () {
      // 只有 none 不可用。
      expect(wifi.isUsable, isTrue);
      expect(offline.isUsable, isFalse);
      expect(const NetworkPath.unknown().isUnknown, isTrue);
    });

    test('same link is detected by kind + generation', () {
      // 同链路由类型 + 代次判定。
      expect(wifi.isSameLinkAs(wifi.copyWith()), isTrue);
      expect(wifi.isSameLinkAs(wifiRoamed), isFalse);
    });
  });

  group('NetworkPathChange', () {
    test('Wi-Fi to cellular requires an ICE restart', () {
      // Wi-Fi 切蜂窝需要重启 ICE。
      final change = NetworkPathChange(from: wifi, to: cellular);
      expect(change.kindChanged, isTrue);
      expect(change.becameMetered, isTrue);
      expect(change.requiresIceRestart(), isTrue);
    });

    test('roaming inside Wi-Fi only restarts when opted in', () {
      // Wi-Fi 内漫游仅在显式开启时才重启。
      final change = NetworkPathChange(from: wifi, to: wifiRoamed);
      expect(change.kindChanged, isFalse);
      expect(change.hasChange, isTrue);
      expect(change.requiresIceRestart(), isFalse);
      expect(change.requiresIceRestart(restartOnSameKind: true), isTrue);
    });

    test('losing and restoring a path is classified', () {
      // 失联与恢复路径被正确分类。
      expect(NetworkPathChange(from: wifi, to: offline).isLost, isTrue);
      expect(NetworkPathChange(from: offline, to: wifi).isRestored, isTrue);
      expect(
        NetworkPathChange(from: wifi, to: wifi.copyWith()).hasChange,
        isFalse,
      );
    });
  });

  group('CallbackNetworkMonitor', () {
    test('emits only real changes', () async {
      // 只在真正变化时投递。
      final monitor = CallbackNetworkMonitor(initial: wifi);
      final seen = <NetworkPath>[];
      final sub = monitor.paths.listen(seen.add);
      await monitor.start();
      monitor.update(wifi.copyWith());
      monitor.update(cellular);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(seen.length, 1);
      expect(seen.single.kind, NetworkKind.cellular);
      expect(monitor.current.kind, NetworkKind.cellular);
      expect(monitor.lastChange!.kindChanged, isTrue);
      await sub.cancel();
      await monitor.dispose();
    });
  });

  group('NetworkPathMonitor.fromStream', () {
    test('forwards distinct paths', () async {
      // 转发不同的路径。
      final controller = StreamController<NetworkPath>.broadcast();
      final monitor = NetworkPathMonitor.fromStream(
        controller.stream,
        initial: wifi,
      );
      await monitor.start();
      controller.add(wifi);
      controller.add(cellular);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(monitor.current.kind, NetworkKind.cellular);
      await monitor.dispose();
      await controller.close();
    });
  });
}
