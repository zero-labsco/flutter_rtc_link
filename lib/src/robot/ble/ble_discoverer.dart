import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_device.dart';
import 'flutter_blue_plus_link.dart';

/// Scans for robots advertising the teleop GATT service.
/// 扫描广播了遥测 GATT 服务的机器人。
///
/// Returns plain [BleDevice]s so the example / host app never imports
/// `flutter_blue_plus`. Pick one, then hand it to
/// [BleTeleopChannel.forDevice]. / 返回干净的 [BleDevice]，使示例 / 宿主 app
/// 无需引入 `flutter_blue_plus`。选中一个后交给 [BleTeleopChannel.forDevice]。
class BleTeleopDiscoverer {
  BleTeleopDiscoverer({
    this.serviceUuid = kTeleopServiceUuid,
    this.timeout = const Duration(seconds: 8),
  });

  /// GATT service to filter scan results by. / 用于过滤扫描结果的服务 UUID。
  final String serviceUuid;

  /// Scan window. / 扫描时长。
  final Duration timeout;

  Future<List<BleDevice>> scan() async {
    final found = <String, BleDevice>{};
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        found[id] = BleDevice(
          id: id,
          name: result.advertisementData.advName,
          rssi: result.rssi,
        );
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: <Guid>[Guid(serviceUuid)],
        timeout: timeout,
      );
      await Future<void>.delayed(timeout + const Duration(milliseconds: 300));
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
    return found.values.toList();
  }
}
