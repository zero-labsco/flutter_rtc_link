/// Flutter RTC Link — robot teleoperation module.
/// Flutter RTC Link —— 机器人遥控模块。
///
/// [RobotController] (watchdog + epoch gating) and the control-channel
/// abstractions: MQTT, WebRTC data channel, BLE, or a dual path.
/// [RobotController]（看门狗 + epoch 门控）以及控制通道抽象：MQTT、WebRTC
/// 数据通道、BLE 或双路冗余。
///
/// Three channels stay separated: media (WebRTC), control (MQTT /
/// DataChannel) and business (HTTPS) never mix.
/// 三条通道保持分离：媒体（WebRTC）、控制（MQTT / DataChannel）与业务
/// （HTTPS）互不混用。
///
/// This entry point is independent of the device module: importing it never
/// pulls provisioning / OTA code in. The resilience types used by
/// [RobotController] ([PauseResumeGate], [CommandRateLimiter]) are re-exported
/// here so the module is usable on its own.
/// 本入口与设备模块相互独立：导入它绝不会引入配网 / OTA 代码。[RobotController]
/// 用到的韧性层类型（[PauseResumeGate]、[CommandRateLimiter]）在此一并再导出，
/// 使本模块可独立使用。
library;

export 'src/core/rtc_credentials.dart';

// Resilience types required by RobotController's public API. /
// RobotController 公开 API 所需的韧性层类型。
export 'src/resilience/control_link.dart';
export 'src/resilience/pause_resume_gate.dart';

export 'src/robot/robot_controller.dart';
export 'src/robot/robot_events.dart';
export 'src/robot/teleop_channel.dart';

// BLE control link. / BLE 控制链路。
export 'src/ble/ble_device.dart';
export 'src/robot/ble/ble_discoverer.dart';
export 'src/robot/ble/ble_link.dart';
export 'src/robot/ble/ble_teleop_channel.dart';
export 'src/robot/ble/flutter_blue_plus_link.dart';
