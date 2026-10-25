import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../robot/ble/ble_device.dart';

/// Generic BLE scanner returning plain [BleDevice]s for any nearby device.
/// 通用 BLE 扫描器：返回附近任意设备的干净 [BleDevice]。
///
/// Unlike [BleTeleopDiscoverer] (robot / teleop-focused) this scanner makes no
/// protocol assumption. Pass [serviceUuids] to narrow results to devices
/// advertising those services, or omit it to list everything nearby (handy for
/// inspecting / connecting to non-robot hardware such as speakers or sensors).
/// 与仅聚焦机器人的 [BleTeleopDiscoverer] 不同，本扫描器不做协议假设。传入
/// [serviceUuids] 可只列出广播了这些服务的设备；留空则列出附近全部设备——
/// 适合检视 / 连接音响、传感器等非机器人硬件。
class BleScanner {
  BleScanner({this.timeout = const Duration(seconds: 8)});

  /// Scan window. / 扫描时长。
  final Duration timeout;

  /// Scans for nearby devices. / 扫描附近设备。
  ///
  /// When [serviceUuids] is provided, only devices advertising at least one of
  /// those services are returned. / 提供 [serviceUuids] 时只返回广播了其中任一
  /// 服务的设备。
  Future<List<BleDevice>> scan({List<String>? serviceUuids}) async {
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
        // An empty service filter lists every advertising device. /
        // 空服务过滤会列出所有广播中的设备。
        withServices: serviceUuids?.map((u) => Guid(u)).toList() ?? <Guid>[],
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
