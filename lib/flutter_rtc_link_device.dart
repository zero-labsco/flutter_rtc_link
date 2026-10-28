/// Flutter RTC Link — IoT device management module.
/// Flutter RTC Link —— 物联网设备管理模块。
///
/// Provisioning (BLE / DPP / NFC / SmartConfig), OTA, log collection and
/// diagnostics, plus a protocol-agnostic BLE client for any peripheral.
/// 配网（BLE / DPP / NFC / SmartConfig）、OTA、日志采集与诊断，以及面向任意
/// 外设的与协议无关的 BLE 客户端。
///
/// This entry point is independent of the robot module: importing it never
/// pulls teleoperation code in. Pair it with
/// `package:flutter_rtc_link/flutter_rtc_link.dart` when you also need media.
/// 本入口与机器人模块相互独立：导入它绝不会引入遥控代码。若同时需要媒体能力，
/// 请一并导入 `package:flutter_rtc_link/flutter_rtc_link.dart`。
library;

export 'src/core/rtc_credentials.dart';

export 'src/device/device_events.dart';
export 'src/device/diagnostics.dart';
export 'src/device/log_collector.dart';
export 'src/device/ota_updater.dart';
export 'src/device/provisioning.dart';
export 'src/device/provisioning_channels.dart';

// Protocol-agnostic BLE (discovery + raw GATT read/write/notify) for any
// device — speaker, sensor, peripheral — not just robots. / 与协议无关的通用
// BLE（发现 + 原始 GATT 读写/通知），适用于任意设备——音响、传感器、外设等，
// 不限于机器人。
export 'src/ble/ble_device.dart';
export 'src/ble/ble_gatt_client.dart';
export 'src/ble/ble_scanner.dart';
