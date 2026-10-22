# Changelog

## 0.1.0

### Added / 新增
- Initial release of `flutter_rtc_link`: a Flutter plugin for real-time audio/video and IoT device management with a dual-engine architecture (`WhipWhepEngine` over `flutter_webrtc`, `LiveKitEngine` over `livekit_client`) behind one unified abstraction (`RtcEngine` / `RtcSession` / `LocalPublisher` / `RemoteSubscriber`).
  - `flutter_rtc_link` 首个版本：实时音视频 + 物联网设备管理插件，双引擎架构（基于 `flutter_webrtc` 的 `WhipWhepEngine` 与基于 `livekit_client` 的 `LiveKitEngine`）统一抽象（`RtcEngine` / `RtcSession` / `LocalPublisher` / `RemoteSubscriber`）。
- Lead-operator publishing with simulcast: `startCamera` / `startMic` / `startScreenShare`, zero-renegotiation `switchCamera` via `replaceTrack` (RFC 9725 friendly), and `setPublishClarity` that caps the top simulcast layer.
  - 牵头操作者推流（simulcast 多层）：`startCamera` / `startMic` / `startScreenShare`、经 `replaceTrack` 的零重协商 `switchCamera`（符合 RFC 9725），以及只限制最高层的 `setPublishClarity`。
- Subscription and picture switching: WHEP playback, per-stream `RemoteSubscriber.setClarity`, and a pure-Dart `VideoGridController` (main/pip/grid layouts, max visible, global clarity).
  - 订阅与画面切换：WHEP 拉流、每路独立的 `RemoteSubscriber.setClarity`，以及纯 Dart 的 `VideoGridController`（主画面 / 画中画 / 网格布局、最大可见数、全局清晰度）。
- Live relay: `RoleTransfer.promote` / `handover` (identity handover) and `StreamRelay.toRtmp` / `cascade` (server-side Egress or secondary WHIP push).
  - 直播转接：`RoleTransfer.promote` / `handover`（身份交接）与 `StreamRelay.toRtmp` / `cascade`（服务端 Egress 或二次 WHIP 推流）。
- Robot teleoperation: `RobotController` with joystick velocity integration, PTZ, telemetry, voice intercom hookup, and a 500 ms watchdog that auto-stops the robot on command timeout or link loss.
  - 机器人远控：`RobotController` 支持摇杆速度积分、云台 PTZ、遥测、语音对讲接入，以及指令超时 / 断链 500ms 内自动停车的看门狗保护。
- IoT device management suite: multi-channel `DeviceProvisioning` (BLE → DPP/QR → NFC → SoftAP → SmartConfig strategy chain with automatic degradation), `OtaUpdater` (BLE/HTTP with SHA-256 verification), `DeviceLogCollector` (local cache + batch upload), and `Diagnostics` (WebRTC stats + network probe + device logs → JSON/Markdown report).
  - 物联网设备管理四件套：多通道 `DeviceProvisioning`（BLE → DPP/QR → NFC → SoftAP → SmartConfig 策略链，失败自动降级）、`OtaUpdater`（BLE/HTTP，SHA-256 校验）、`DeviceLogCollector`（本地缓存 + 批量补传）、`Diagnostics`（WebRTC stats + 网络探测 + 设备日志 → JSON/Markdown 报告）。
- Unified permission gate `RtcPermissions.requestAll(capabilities)` covering the Android 13/14+ and iOS pitfalls (foreground-service microphone, nearby Wi-Fi devices, NFC entitlement); denials degrade features and emit `RtcEvent.permissionDenied` instead of crashing.
  - 统一权限入口 `RtcPermissions.requestAll(capabilities)`，覆盖 Android 13/14+ 与 iOS 的权限坑（前台服务麦克风、附近 Wi-Fi 设备、NFC entitlement）；权限被拒时功能降级并上报 `RtcEvent.permissionDenied`，不崩溃。
- Native modules: Android DPP (Wi-Fi Easy Connect) platform channel and a microphone foreground service; iOS Swift method-channel stub. Method channel prefix `pkg.flutter.dev/rtc_link/` with centralized `RtcErrorCodes`.
  - 原生模块：Android DPP（Wi-Fi Easy Connect）平台通道与麦克风前台服务；iOS Swift method channel 桩。Method channel 前缀 `pkg.flutter.dev/rtc_link/`，错误码集中定义于 `RtcErrorCodes`。
- Ready-to-run example app (publish/subscribe, robot joystick, device management demos) and unit tests for the layout, clarity, relay, watchdog, provisioning, log-cache and diagnostics paths.
  - 可直接运行的 example 应用（推流 / 订阅、机器人摇杆、设备管理演示）以及布局、清晰度、转接、看门狗、配网、日志缓存与诊断路径的单元测试。
- Resilience layer for overseas / cross-public-network links: `ResilientSession` (supervised connect, jittered backoff reconnect with automatic re-subscription), `RelayPlanner` (per-region TURN ordering + `RelayMode.forced` escalation for CGNAT / cross-border paths), `NetworkPathMonitor` (Wi-Fi ↔ cellular handover → ICE restart) and `MediaHealthMonitor` (stutter / congestion / frozen-picture detection with keyframe → downgrade → re-subscribe recovery).
  - 面向海外 / 跨公网链路的韧性层：`ResilientSession`（受控建链、带抖动退避重连并自动重新订阅）、`RelayPlanner`（按区域排序 TURN + 面向 CGNAT / 跨境路径的 `RelayMode.forced` 升级）、`NetworkPathMonitor`（Wi-Fi ↔ 蜂窝切换触发 ICE 重启）与 `MediaHealthMonitor`（卡顿 / 拥塞 / 画面冻结检测，并按请求关键帧 → 降档 → 重建订阅逐级恢复）。
- App-side pause/resume confirmation flow: `PauseResumeGate` stamps every operation with an epoch; pausing bumps the epoch so buffered operations are dropped instead of replayed, and resuming is a two-step ticket handshake (`requestResume` → `confirmResume`) that expires. `EpochOperationQueue` adds latest-wins buffering for teleoperation.
  - 应用侧暂停 / 恢复确认流程：`PauseResumeGate` 为每个操作盖上 epoch 戳；暂停会递增 epoch，使缓存操作被丢弃而非补发；恢复是一次会过期的两步票据握手（`requestResume` → `confirmResume`）。`EpochOperationQueue` 为遥控提供"最新者胜"缓冲。
- Low-latency control link helpers: `ControlLinkRouter` (data channel preferred, MQTT fallback, latency budget), `ControlRttTracker` and `CommandRateLimiter`.
  - 低时延控制链路辅助：`ControlLinkRouter`（优先数据通道、回退 MQTT、带时延预算）、`ControlRttTracker` 与 `CommandRateLimiter`。
- `AppLifecycleGate`: maps Flutter lifecycle states (`paused` / `hidden` / `detached`) to background suspension and drives the pause/resume gate.
  - `AppLifecycleGate`：把 Flutter 生命周期状态（`paused` / `hidden` / `detached`）映射为后台暂停，并驱动暂停 / 恢复门。

### Changed / 变更
- `RobotController` accepts an optional `PauseResumeGate` and `CommandRateLimiter`; `pause()` stops the robot immediately and invalidates every command issued before it, and the keepalive loop never replays a pre-pause velocity.
  - `RobotController` 可接收可选的 `PauseResumeGate` 与 `CommandRateLimiter`；`pause()` 立即停车并让此前所有指令失效，保活循环绝不补发暂停前的速度。
- `WhipWhepSession` implements `IceRestartable`: handover now rebuilds the peer connections with a fresh ICE configuration (WHIP/WHEP forbids renegotiation, RFC 9725).
  - `WhipWhepSession` 实现了 `IceRestartable`：切换时会用全新的 ICE 配置重建 peer connection（RFC 9725 规定 WHIP/WHEP 不可重协商）。
