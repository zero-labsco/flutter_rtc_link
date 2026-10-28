/// Flutter RTC Link — real-time audio/video (WebRTC) core module.
/// Flutter RTC Link —— 实时音视频（WebRTC）核心模块。
///
/// This is the **media core**: dual engines behind one abstraction, plus the
/// resilience layer that keeps a link alive in the real world.
/// 这是**媒体核心**：双引擎统一抽象，外加让链路在真实环境中活下去的韧性层。
///
/// - [WhipWhepEngine] over `flutter_webrtc` (WHIP/WHEP, RFC 9725).
/// - [LiveKitEngine] over `livekit_client` (room semantics).
///
/// Wrap any session in [ResilientSession] to survive overseas
/// cross-public-network paths, TURN relay escalation, Wi-Fi ↔ cellular
/// handover, weak-network stalls and app backgrounding. [PauseResumeGate]
/// guarantees that no operation produced before an interruption is ever
/// replayed after the link comes back.
/// 用 [ResilientSession] 包装任意会话即可应对海外跨公网路径、TURN 中继升级、
/// Wi-Fi ↔ 蜂窝切换、弱网卡顿与应用后台。[PauseResumeGate] 保证中断前产生的
/// 操作绝不会在链路恢复后被补发。
///
/// Feature modules are separate entry points so that an app which only needs
/// media never compiles them in:
/// 功能模块是独立入口，只需要媒体能力的应用不会把它们编译进来：
/// - `package:flutter_rtc_link/flutter_rtc_link_device.dart` — provisioning,
///   OTA, log collection, diagnostics, generic BLE.
/// - `package:flutter_rtc_link/flutter_rtc_link_robot.dart` — robot
///   teleoperation and the BLE control link.
library;

// Core abstractions. / 核心抽象。
export 'src/core/rtc_credentials.dart';
export 'src/core/rtc_engine.dart';
export 'src/core/rtc_events.dart';
export 'src/core/rtc_role.dart';
export 'src/core/rtc_session.dart';
export 'src/core/rtc_signaling.dart';
export 'src/core/rtc_stats.dart';

// Engines. / 引擎。
export 'src/engines/livekit_engine.dart';
export 'src/engines/whip_client.dart';
export 'src/engines/whip_whep_engine.dart';

// Publishing and subscribing. / 推流与订阅。
export 'src/publishers/local_publisher.dart';
export 'src/publishers/simulcast.dart';
export 'src/subscribers/remote_subscriber.dart';
export 'src/subscribers/video_grid_controller.dart';

// Relay. / 转接。
export 'src/relay/role_transfer.dart';
export 'src/relay/stream_relay.dart';

// Resilience. / 韧性层。
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

// Platform integration. / 平台集成。
export 'src/platforms/lan_discovery.dart';
export 'src/platforms/rtc_link_platform.dart';
export 'src/platforms/rtc_permissions.dart';

// Widgets. / 组件。
export 'src/widgets/joystick.dart';
export 'src/widgets/rtc_control_bar.dart';
export 'src/widgets/rtc_video_view.dart';
