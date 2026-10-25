# Changelog

## 0.3.1

### Fixed / 修复
- Project-wide bug sweep: resource leaks, crash paths and protocol correctness
  across every module. / 全项目缺陷清理：各模块的资源泄漏、崩溃路径与协议正确性。
  - `protocomm`: AES-CTR dropped the intra-block remainder, so every message
    after a non-16-byte payload was garbled — the counter now follows one
    continuous keystream. / AES-CTR 丢弃块内余数，导致非 16 字节整数倍载荷之后
    的所有消息错位——计数器现遵循一条连续 keystream。
  - `protocomm`: `setup1` failed open, so a device omitting `SessionResp1`
    skipped Proof-of-Possession authentication; it now raises. / setup1 失败
    开放，省略 SessionResp1 的设备会跳过所有权证明鉴权；现在改为抛错。
  - `PbReader` / `PbWriter`: bounds checks, malformed-field tolerance and a
    negative varint guard. / 边界检查、畸形字段容错与负数 varint 防护。
  - OTA: verify the server's resume start offset, reuse a single `http.Client`,
    and release the BLE link on failure (`try/finally`). / 校验服务端续传起始
    偏移、复用单个 http.Client，并在失败时释放 BLE 连接。
  - Log collector: verify the MQTT connection (batches were silently dropped),
    disconnect stale clients, guard concurrent flushes and tolerate corrupt
    cache lines. / 校验 MQTT 连接（此前批次被静默丢弃）、释放旧 client、防并发
    flush 并容忍损坏的缓存行。
  - Provisioning: poll for a terminal Wi-Fi state instead of reading it once;
    release the scan subscription when scanning throws. / 轮询终态 Wi-Fi 状态
    而非只读一次；扫描抛错时释放扫描订阅。
  - BLE: `BleTeleopChannel.dispose` now stops the transport (a failed connect
    left the auto-reconnect timer running); the link clears stale characteristic
    handles on reconnect, resets its retry budget, guards concurrent connects
    and closes its controllers. / dispose 现在停止传输层（连接失败后自动重连
    定时器仍在运行）；链路在重连时清除陈旧特征句柄、重置重试预算、防并发连接并
    关闭控制器。
  - `DualTeleopChannel`: no longer crashes when `disconnect()` runs before
    `connect()`, and can be reconnected afterwards. / 在 connect() 之前调用
    disconnect() 不再崩溃，且之后可重新连接。
  - MQTT teleop: guard concurrent connects, release the previous client and
    subscription, verify the connection state and tolerate non-JSON telemetry.
    / 防并发连接、释放旧 client 与订阅、校验连接状态并容忍非 JSON 遥测。
  - Resilience: dispose the previous session on reconnect (it was only left),
    serialise attaches, re-check `disposed` after awaits, rate-limit recovery
    actions, re-enable video after reconnect, only stop the robot on a
    background pause, require a session in `confirmResume` and clear orphan
    resume tickets. / 重连时释放前一个会话（此前仅 leave）、串行化 attach、await
    后复检 disposed、恢复动作限流、重连后重新开启视频、仅在后台暂停时停车、
    confirmResume 要求会话存在并清除孤儿恢复票据。
  - WHIP/WHEP: drain responses, close the HTTP client, resolve relative
    `Location` headers, buffer trickle ICE candidates until the resource exists,
    guard concurrent peer-connection creation and clean up on failure. / 排空
    响应、关闭 HTTP 客户端、解析相对 Location 头、缓存 trickle ICE 候选直到资源
    就绪、防并发建连并在失败时清理。
  - `simulcast`: every `case` now breaks — falling through made all layers end
    up at `full ~/ 4`. / 每个 case 现在都 break——直通会让所有层最终变成
    full ~/ 4。
  - Emits after `dispose()` are ignored instead of throwing. / dispose() 之后
    的 emit 被忽略而非抛异常。
  - LAN discovery: stop a discovery cancelled before it started, and surface
    errors instead of losing them. / 停止启动前被取消的 discovery，并上报错误
    而非丢失。
  - Scanners: drop the previous scan's replayed results and handle stream
    errors. / 丢弃上一次扫描的回放结果并处理流错误。
  - `stream_relay`: `stop()` catches every error (not just `RtcException`) so
    cleanup always finishes, and releases the Egress HTTP client. / stop() 捕获
    所有异常（不只 RtcException）以保证清理完成，并释放 Egress HTTP 客户端。

## 0.3.0

### Added / 新增
- Persistent BLE GATT teleop control channel. / 基于 BLE GATT 的持久控制通道。
  - `BleTeleopChannel implements TeleopChannel` drops straight into `RobotController` / `DualTeleopChannel` — the watchdog, epoch gating and keepalive are unchanged; only the transport changes. / `BleTeleopChannel implements TeleopChannel`，可直接接入 `RobotController` / `DualTeleopChannel`——看门狗、epoch 门控与保活逻辑不变，仅传输换了。
  - `FlutterBluePlusBleLink` resolves the GATT service + command/telemetry characteristics, negotiates a larger MTU (256), subscribes to telemetry notifications, and auto-reconnects on a drop (capped, exponential backoff). / `FlutterBluePlusBleLink` 解析 GATT 服务与指令 / 遥测特征、协商更大 MTU（256）、订阅遥测通知，并在断线后自动重连（有上限、指数退避）。
  - `BleTeleopDiscoverer` scans for the teleop GATT service; `BleDevice` keeps the public API free of `flutter_blue_plus` types. Command/telemetry reuse the JSON envelopes of the other channels. / `BleTeleopDiscoverer` 扫描遥测 GATT 服务；`BleDevice` 让公开 API 不暴露 `flutter_blue_plus` 类型。指令 / 遥测复用其它通道的 JSON 封包。
  - Example `ble_control_demo_page` and website docs (`ble_control.md`, `zh/`) with the GATT contract. / 示例 `ble_control_demo_page` 与文档站（`ble_control.md`、中文版）含 GATT 契约。
- Protocol-agnostic BLE for any device (speaker, sensor, peripheral — not just robots). / 面向任意设备（音响、传感器、外设——不限于机器人）的、与协议无关的通用 BLE。
  - `BleScanner` discovers nearby devices with no service filter (or narrowed to `serviceUuids`), returning the same `BleDevice` the teleop path uses. / `BleScanner` 无需服务过滤即可发现附近设备（也可按 `serviceUuids` 收敛），返回与遥测路径相同的 `BleDevice`。
  - `BleGattClient` connects to a `BleDevice`, discovers services, and exposes raw `read` / `write` / `subscribe` plus a `connectionState` stream — no teleop / ESP contract assumed. / `BleGattClient` 连接 `BleDevice`、发现服务，并暴露原始的 `read` / `write` / `subscribe` 与连接状态流——不做任何遥测 / ESP 契约假设。
  - `BleScanner` and `BleGattClient` are exported from the package root and built on `flutter_blue_plus`, keeping exactly one Bluetooth library in the dependency tree. / `BleScanner` 与 `BleGattClient` 均从包根导出，基于 `flutter_blue_plus`，使依赖树中恰好只有一个蓝牙库。
  - Example `ble_control_demo_page` adds a **Teleop / All devices** toggle: "All devices" connects via `BleGattClient` and shows the GATT services / characteristics (tap a readable characteristic to read it). / 示例 `ble_control_demo_page` 新增 **Teleop / All devices** 切换："All devices" 经 `BleGattClient` 连接并展示 GATT 服务 / 特征（点击可读取的特征即可读取值）。

## 0.2.0

### Added / 新增
- 4K (2160p) publish support. / 4K（2160p）发布支持。
  - New `ClarityLevel.p2160` (height 2160, label `2160p`, suggested full-layer cap 8000 kbps). / 新增 `ClarityLevel.p2160`（高度 2160，标签 `2160p`，满层建议码率上限 8000 kbps）。
  - LiveKit `capturePresetFor` / `simulcastLayersFor` now map `p2160` to `VideoParametersPresets.h2160_169` (capture 3840×2160 with 180p/540p/1080p/2160p simulcast layers). / LiveKit 的 `capturePresetFor` / `simulcastLayersFor` 现在将 `p2160` 映射到 `h2160_169`（采集 3840×2160，simulcast 层为 180p/540p/1080p/2160p）。
  - WHIP/WHEP publishers derive the 16:9 capture width from the clarity height, so `p2160` automatically requests 3840×2160. / WHIP/WHEP 推流器按清晰度高度推导 16:9 采集宽度，`p2160` 自动请求 3840×2160。
  - Clarity selector UI in `RtcControlBar` and the example `rtc_demo_page` now offer `2160p`. / `RtcControlBar` 与示例 `rtc_demo_page` 的清晰度选择器现已提供 `2160p`。
  - `fromHeight` maps 1080p < height ≤ 2160 to `p2160`, and `degradeClarity` ladder starts at `p2160`. / `fromHeight` 将 1080p < 高度 ≤ 2160 映射为 `p2160`，`degradeClarity` 阶梯顶端为 `p2160`。

### Fixed / 修复
- Negative bitrate after ICE restart / network handover: `RtcStatsSampler` compared the new peer connection's byte counter (which resets to ~0) against the previous cumulative baseline, producing a bogus negative `bitrateKbps` for one sample. The sampler now treats a counter reset as zero bitrate, and `WhipWhepPublisher.restartIce` resets both the video and audio samplers. `RtcStatsSampler` also accepts an injectable clock for deterministic tests.
  - ICE 重启 / 网络切换后的负码率：`RtcStatsSampler` 会把新 peer connection 的字节计数器（归零）与之前累计的基线比较，导致某一帧 `bitrateKbps` 出现虚假负值。现改为将计数器重置视为零码率，且 `WhipWhepPublisher.restartIce` 会同时重置视频与音频采样器。`RtcStatsSampler` 现支持注入可测时钟。

## 0.1.3

### Added / 新增
- `LocalPublisher.cameraStream` (flutter_webrtc `MediaStream?`): exposes the camera media stream so consumers can render a local preview with a full `MediaStream` (binding only a track id does not render on Android). `WhipWhepPublisher` populates it from the active capture stream; `LiveKitPublisher` returns `null` (LiveKit previews its own tracks via `lk.VideoTrackRenderer`, not a flutter_webrtc stream).
  - `LocalPublisher.cameraStream`（`flutter_webrtc` 的 `MediaStream?`）：暴露摄像头媒体流，便于消费者用完整 `MediaStream` 渲染本地预览（只绑 track id 在 Android 上不会出画）。`WhipWhepPublisher` 从当前采集流填充该值；`LiveKitPublisher` 返回 `null`（LiveKit 经自身的 `lk.VideoTrackRenderer` 渲染预览，不依赖 flutter_webrtc 的 stream）。

### Changed / 变更
- Raised the `permission_handler` constraint from `^11.0.0` to `^12.0.0`. 12.0.0 only requires Android `compileSdk 35` (its `permission_handler_android` submodule is 13.0.0), which is still ≤ the default Flutter template's 36, so the AGP 9.1.0 / compileSdk 36 build is unaffected and the earlier "API ≤ 36" rationale still holds. The plugin's own usage of `permission_handler` (the `Permission` enum, `request()`, `status`, `openAppSettings()`) is unchanged.
  - 将 `permission_handler` 约束由 `^11.0.0` 提升到 `^12.0.0`。12.0.0 仅需 Android `compileSdk 35`（底层 `permission_handler_android` 子模块为 13.0.0），仍 ≤ 默认 Flutter 模板的 36，因此 AGP 9.1.0 / compileSdk 36 构建不受影响，先前"API ≤ 36"的考量依旧成立；插件对其 Dart API（`Permission` 枚举、`request()`、`status`、`openAppSettings()`）的用法无变更。

## 0.1.2

### Fixed / 修复
- Example app device-page action row overflow on narrow screens: the SCAN BLE / DPP / NFC buttons were laid out in a fixed three-up `Row` that overflowed; they now wrap so they flow to the next line when space is tight.
  - 示例应用设备页操作行在窄屏溢出：SCAN BLE / DPP / NFC 原本排成固定三列 `Row` 会溢出；现已改为自动换行。
- Lowered the `permission_handler` constraint to `^11.0.0` so its Android submodule stays at API ≤ 36, keeping the default Flutter template (AGP 9.1.0 / compileSdk 36) buildable without forcing an AGP / Gradle upgrade.
  - 将 `permission_handler` 约束降到 `^11.0.0`，使其 Android 子模块停留在 API ≤ 36，从而默认 Flutter 模板（AGP 9.1.0 / compileSdk 36）无需升级 AGP / Gradle 即可构建。

## 0.1.1

### Fixed / 修复
- Joystick crash on first release: `_animation` was declared `late final` but reassigned in `_release()`, throwing `LateInitializationError`. It is now a reassignable `late` field.
  - 摇杆首次松手崩溃：`_animation` 被声明为 `late final` 却在 `_release()` 中二次赋值，抛 `LateInitializationError`；现改为可重新赋值的 `late` 字段。
- LiveKit multi-stream subscription revocation: subscribing a second stream overwrote the track-subscription allowlist and revoked the first. Wanted track SIDs are now accumulated per participant and re-granted together.
  - LiveKit 多路订阅互相撤销：订阅第二路时覆盖轨道订阅白名单、撤销第一路；现按参与者累加想要的轨道 SID 并统一重新授权。
- ResilientSession re-entrant reconnect double scheduling: the `_recovering` guard was set after `await pause()`, letting two racing events both schedule a backoff timer. The guard is now taken synchronously before the await.
  - ResilientSession 重入重连双调度：`_recovering` 守卫在 `await pause()` 之后才置位，两类并发事件可同时穿过并各调度一个退避定时器；现改为在 await 前同步加锁。
- ResilientSession never emitted `RtcConnected`: the session's own `RtcConnected` was suppressed in `_onSessionEvent` but never re-emitted by `ResilientSession`, so consumers never learned a link was (re)established. It is now emitted from `_establish`.
  - ResilientSession 从不对外发出 `RtcConnected`：会话自身的 `RtcConnected` 在 `_onSessionEvent` 中被抑制，而 `ResilientSession` 又从未补发，导致消费者永远收不到连接成功事件；现由 `_establish` 补发。
- `setBackground(false)` duplicate resume: when `autoResumeAfterReconnect` is enabled, `_afterReconnect` already resumed the gate, yet the foreground path requested a second (orphaned) resume ticket. The foreground path now skips resume in that case.
  - `setBackground(false)` 重复恢复：开启 `autoResumeAfterReconnect` 时 `_afterReconnect` 已处理门的恢复，回到前台又发起一个被废弃的恢复票据；现已在该情况下跳过。
- LanDiscovery.discoverStream early-cancel crash: `onCancel` touched `late` discovery/listener fields that were not yet initialized if the stream was cancelled before `startDiscovery` resolved, throwing `LateInitializationError`. They are now nullable with null checks.
  - LanDiscovery.discoverStream 提前取消崩溃：`onCancel` 访问尚未初始化的 `late` 字段（流在 `startDiscovery` 完成前被取消时），抛 `LateInitializationError`；现改为可空并加空判断。

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
