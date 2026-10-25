/// Flutter RTC Link — real-time audio/video (WebRTC) and IoT device
/// management in one plugin. / Flutter RTC Link —— 实时音视频（WebRTC）与
/// 物联网设备管理一体化插件。
///
/// Dual engines behind one abstraction:
/// - [WhipWhepEngine] over `flutter_webrtc` (WHIP/WHEP, RFC 9725).
/// - [LiveKitEngine] over `livekit_client` (room semantics).
///
/// 双引擎、统一抽象：
/// - [WhipWhepEngine] 基于 `flutter_webrtc`（WHIP/WHEP，RFC 9725）；
/// - [LiveKitEngine] 基于 `livekit_client`（房间语义）。
///
/// Wrap any session in [ResilientSession] to survive the real world: overseas
/// cross-public-network paths, TURN relay escalation, Wi-Fi ↔ cellular
/// handover, weak-network stalls and app backgrounding. [PauseResumeGate]
/// guarantees that no operation produced before an interruption is ever
/// replayed after the link comes back.
/// 用 [ResilientSession] 包装任意会话即可应对真实环境：海外跨公网路径、TURN
/// 中继升级、Wi-Fi ↔ 蜂窝切换、弱网卡顿与应用后台。[PauseResumeGate] 保证
/// 中断前产生的操作绝不会在链路恢复后被补发。
library;

export 'src/core/rtc_engine.dart';
export 'src/core/rtc_events.dart';
export 'src/core/rtc_role.dart';
export 'src/core/rtc_session.dart';
export 'src/core/rtc_signaling.dart';
export 'src/core/rtc_stats.dart';
export 'src/device/diagnostics.dart';
export 'src/device/log_collector.dart';
export 'src/device/ota_updater.dart';
export 'src/device/provisioning.dart';
export 'src/device/provisioning_channels.dart';
export 'src/engines/livekit_engine.dart';
export 'src/engines/whip_client.dart';
export 'src/engines/whip_whep_engine.dart';
export 'src/platforms/lan_discovery.dart';
export 'src/platforms/rtc_link_platform.dart';
export 'src/platforms/rtc_permissions.dart';
export 'src/publishers/local_publisher.dart';
export 'src/publishers/simulcast.dart';
export 'src/relay/role_transfer.dart';
export 'src/resilience/app_lifecycle_gate.dart';
export 'src/resilience/control_link.dart';
export 'src/resilience/link_events.dart';
export 'src/resilience/link_policy.dart';
export 'src/resilience/media_health.dart';
export 'src/resilience/network_path.dart';
export 'src/resilience/pause_resume_gate.dart';
export 'src/resilience/reconnect_supervisor.dart';
export 'src/resilience/relay_policy.dart';
export 'src/resilience/resilient_session.dart';
export 'src/relay/stream_relay.dart';
export 'src/robot/ble/ble_device.dart';
export 'src/robot/ble/ble_discoverer.dart';
export 'src/robot/ble/ble_link.dart';
export 'src/robot/ble/ble_teleop_channel.dart';
export 'src/robot/ble/flutter_blue_plus_link.dart';
export 'src/robot/robot_controller.dart';
export 'src/robot/teleop_channel.dart';
export 'src/subscribers/remote_subscriber.dart';
export 'src/subscribers/video_grid_controller.dart';
export 'src/widgets/joystick.dart';
export 'src/widgets/rtc_control_bar.dart';
export 'src/widgets/rtc_video_view.dart';
