# Changelog

## 0.4.0

### Added / 新增

- Added separate public entry points `flutter_rtc_link_device.dart` (provisioning, OTA, logs, diagnostics, generic BLE) and `flutter_rtc_link_robot.dart` (teleoperation, BLE control link), so an app that only needs media no longer compiles those modules, and added `tool/check_module_boundaries.dart` to enforce the module directions in CI.
  - 新增独立公开入口 `flutter_rtc_link_device.dart`（配网、OTA、日志、诊断、通用 BLE）与 `flutter_rtc_link_robot.dart`（遥控、BLE 控制链路），只需要媒体能力的应用不再编译这些模块，并新增 `tool/check_module_boundaries.dart` 在 CI 中强制校验模块依赖方向。
- Added `RobotEvent`, a sealed hierarchy in `robot/robot_events.dart` that takes over the telemetry, pause / resume, stale-drop and watchdog events previously hanging off `DeviceEvent`.
  - 新增 `RobotEvent`（位于 `robot/robot_events.dart` 的密封层级），接管此前挂在 `DeviceEvent` 下的遥测、暂停 / 恢复、过期丢弃与看门狗事件。
- Added `NfcTagBackend` and `WifiNetworkConnector`: injectable adapters so the NFC and Wi-Fi stacks are supplied by the app instead of being forced on every consumer of the plugin.
  - 新增 `NfcTagBackend` 与 `WifiNetworkConnector` 可注入适配器，使 NFC 与 Wi-Fi 技术栈由应用提供，而不强加给插件的每个使用者。

### Changed / 优化

- Changed the public barrel `flutter_rtc_link.dart` to export the media core only: device and robot symbols must now be imported from `flutter_rtc_link_device.dart` / `flutter_rtc_link_robot.dart` (breaking, no compatibility shim).
  - 公开 barrel `flutter_rtc_link.dart` 现只导出媒体核心：设备与机器人符号需改从 `flutter_rtc_link_device.dart` / `flutter_rtc_link_robot.dart` 导入（破坏性变更，无兼容垫片）。
- Changed `core/` into a dependency-free shared kernel: `DeviceEvent` moved to `device/device_events.dart`, `MqttCredentials` to `core/rtc_credentials.dart` and `BleDevice` to `ble/ble_device.dart`, so `core` and `resilience` no longer depend on `device`, `robot`, `ble` or `platforms`.
  - 将 `core/` 改为零依赖共享内核：`DeviceEvent` 迁至 `device/device_events.dart`、`MqttCredentials` 迁至 `core/rtc_credentials.dart`、`BleDevice` 迁至 `ble/ble_device.dart`，`core` 与 `resilience` 自此不再依赖 `device`、`robot`、`ble` 或 `platforms`。
- Changed `RobotController.events` to emit `Stream<RobotEvent>` instead of `Stream<DeviceEvent>`; `DeviceEvent` keeps only provisioning, OTA, log and diagnostics events.
  - `RobotController.events` 改为发出 `Stream<RobotEvent>` 而非 `Stream<DeviceEvent>`；`DeviceEvent` 只保留配网、OTA、日志与诊断事件。
- Changed `NfcProvisioningChannelImpl` to require an `NfcTagBackend`, and renamed `WifiIotSoftApChannel` to `SoftApProvisioningChannelImpl` with a required `WifiNetworkConnector`; the demo app wires both with `nfc_manager` and `wifi_iot`.
  - `NfcProvisioningChannelImpl` 现在要求传入 `NfcTagBackend`；`WifiIotSoftApChannel` 更名为 `SoftApProvisioningChannelImpl` 并要求传入 `WifiNetworkConnector`；示例应用用 `nfc_manager` 与 `wifi_iot` 完成接线。
- Dropped the unused `nordic_dfu` dependency and removed `ndef_record`, `nfc_manager` and `wifi_iot` from the published package, cutting four native plugin integrations (and their merged Android permissions) from every install.
  - 移除未使用的 `nordic_dfu` 依赖，并从发布包中删除 `ndef_record`、`nfc_manager` 与 `wifi_iot`，每次安装少引入四个原生插件（及其合并进来的 Android 权限）。

## 0.3.1

### Added / 新增

- Added `LiveKitSubscriber.publication`: exposes the wrapped `RemoteTrackPublication` so callers can read the real track kind.
  - 新增 `LiveKitSubscriber.publication`：暴露被封装的 `RemoteTrackPublication`，便于调用方读取真实轨道类型。
- Added `DeviceProvisioning.readNfcCredential()`: reads a credential tag and returns the credentials without provisioning anything, so the "tap a tag to learn the Wi-Fi password" flow no longer has to misuse `provisionViaNfc()`.
  - 新增 `DeviceProvisioning.readNfcCredential()`：只读取凭据标签并返回凭据、不做任何配网，使"碰一碰拿到 Wi-Fi 密码"的流程不必再误用 `provisionViaNfc()`。
- Added `ProvisionDevice.dppUri`: carries the Wi-Fi Easy Connect bootstrap URI (`DPP:…`) scanned from the device QR code, which is what DPP actually needs.
  - 新增 `ProvisionDevice.dppUri`：承载从设备二维码扫到的 Wi-Fi Easy Connect 引导 URI（`DPP:…`），这才是 DPP 真正需要的内容。

### Changed / 优化

- `provisionViaNfc({ProvisionDevice? device})` now delivers the tag credentials to that device over BLE / SoftAP / SmartConfig, so NFC can actually provision instead of just reading. The extra parameter is optional, so existing calls keep compiling.
  - `provisionViaNfc({ProvisionDevice? device})` 现在会把标签凭据经 BLE / SoftAP / SmartConfig 下发给该设备，NFC 由此能真正完成配网而不只是读取。该参数为可选，既有调用无需改动。

### Fixed / 修复

- Fixed `provisionViaNfc()` reporting `success` after merely reading a tag: nothing was ever sent to a device (and the credentials were dropped), so the status now fails with an explicit message unless a `ProvisionDevice` is supplied.
  - 修复 `provisionViaNfc()` 仅读到标签就上报 `success` 的问题：凭据从未下发给任何设备（且被丢弃），现在未传入 `ProvisionDevice` 时会以明确信息失败。
- Fixed DPP being handed `device.id` (a BLE address or SoftAP SSID) as the QR content: `provisionViaDpp()` now requires a `DPP:` bootstrap URI and rejects anything else as `protocolMismatch` with a readable message, instead of failing opaquely inside the system configurator.
  - 修复把 `device.id`（BLE 地址或 SoftAP SSID）当作 DPP 二维码内容的问题：`provisionViaDpp()` 现在要求 `DPP:` 引导 URI，其余一律按 `protocolMismatch` 并给出可读信息拒绝，而不是在系统配置器里不明原因地失败。

- Fixed `protocomm`'s AES-CTR dropping the intra-block remainder, so every message after a non-16-byte payload was garbled; the counter now follows one continuous keystream.
  - 修复 `protocomm` 的 AES-CTR 丢弃块内余数，导致非 16 字节整数倍载荷之后的所有消息错位；计数器现遵循一条连续 keystream。
- Fixed `protocomm`'s `setup1` failing open, so a device omitting `SessionResp1` skipped Proof-of-Possession authentication; it now raises.
  - 修复 `protocomm` 的 setup1 失败开放，省略 `SessionResp1` 的设备会跳过所有权证明鉴权；现在改为抛错。
- Fixed `PbReader` / `PbWriter`: bounds checks, malformed-field tolerance and a negative varint guard.
  - 修复 `PbReader` / `PbWriter`：补充边界检查、畸形字段容错与负数 varint 防护。
- Fixed OTA: verify the server's resume start offset, reuse a single `http.Client`, and release the BLE link on failure (`try/finally`).
  - 修复 OTA：校验服务端续传起始偏移、复用单个 `http.Client`，并在失败时（`try/finally`）释放 BLE 连接。
- Fixed the log collector: verify the MQTT connection (batches were silently dropped), disconnect stale clients, guard concurrent flushes and tolerate corrupt cache lines.
  - 修复日志采集器：校验 MQTT 连接（此前批次被静默丢弃）、释放旧 client、防并发 flush 并容忍损坏的缓存行。
- Fixed provisioning: poll for a terminal Wi-Fi state instead of reading it once, and release the scan subscription when scanning throws.
  - 修复配网：轮询终态 Wi-Fi 状态而非只读一次，并在扫描抛错时释放扫描订阅。
- Fixed BLE: `BleTeleopChannel.dispose()` now stops the transport (a failed connect left the auto-reconnect timer running), and the link clears stale characteristic handles on reconnect, resets its retry budget, guards concurrent connects and closes its controllers.
  - 修复 BLE：`BleTeleopChannel.dispose()` 现在停止传输层（连接失败后自动重连定时器仍在运行），链路在重连时清除陈旧特征句柄、重置重试预算、防并发连接并关闭控制器。
- Fixed `DualTeleopChannel` crashing when `disconnect()` runs before `connect()`; it can be reconnected afterwards.
  - 修复 `DualTeleopChannel` 在 `connect()` 之前调用 `disconnect()` 会崩溃的问题；之后可重新连接。
- Fixed MQTT teleop: guard concurrent connects, release the previous client and subscription, verify the connection state and tolerate non-JSON telemetry.
  - 修复 MQTT 遥操作：防并发连接、释放旧 client 与订阅、校验连接状态并容忍非 JSON 遥测。
- Fixed resilience: dispose the previous session on reconnect (it was only left), serialise attaches, re-check `disposed` after awaits, rate-limit recovery actions, re-enable video after reconnect, only stop the robot on a background pause, require a session in `confirmResume()` and clear orphan resume tickets.
  - 修复韧性层：重连时释放前一个会话（此前仅 leave）、串行化 attach、await 后复检 disposed、恢复动作限流、重连后重新开启视频、仅在后台暂停时停车、`confirmResume()` 要求会话存在并清除孤儿恢复票据。
- Fixed WHIP/WHEP: drain responses, close the HTTP client, resolve relative `Location` headers, buffer trickle ICE candidates until the resource exists, guard concurrent peer-connection creation and clean up on failure.
  - 修复 WHIP/WHEP：排空响应、关闭 HTTP 客户端、解析相对 `Location` 头、缓存 trickle ICE 候选直到资源就绪、防并发建连并在失败时清理。
- Fixed `simulcast`: every `case` now breaks — falling through made all layers end up at `full ~/ 4`.
  - 修复 simulcast：每个 case 现在都 break——直通会让所有层最终变成 `full ~/ 4`。
- Fixed emits after `dispose()` throwing "Cannot add event after closing": they are now ignored.
  - 修复 `dispose()` 之后的 emit 抛 "Cannot add event after closing" 的问题：现在改为忽略。
- Fixed LAN discovery: stop a discovery cancelled before it started, and surface errors instead of losing them.
  - 修复 LAN 发现：停止启动前被取消的 discovery，并上报错误而非将其丢失。
- Fixed the scanners: drop the previous scan's replayed results and handle stream errors.
  - 修复扫描器：丢弃上一次扫描的回放结果并处理流错误。
- Fixed `stream_relay.stop()` catching only `RtcException`: it now catches every error so cleanup always finishes, and releases the Egress HTTP client.
  - 修复 `stream_relay.stop()` 只捕获 `RtcException` 的问题：现在捕获所有异常以保证清理完成，并释放 Egress HTTP 客户端。
- Fixed LiveKit: `dispose()` is now idempotent on both the engine and the session, joining a disposed engine is rejected, and `unsubscribe()` reports the real track kind instead of always claiming video.
  - 修复 LiveKit：引擎与会话的 `dispose()` 现在幂等、已释放的引擎拒绝入会、`unsubscribe()` 上报真实轨道类型而非一律声称视频。
- Fixed `NetworkPath.isSameLinkAs()`: a metered flip now counts as a different link, so a hotspot that starts charging triggers a policy re-evaluation.
  - 修复 `NetworkPath.isSameLinkAs()`：计费状态翻转现在算作另一条链路，开始计费的热点会触发策略重算。
- Fixed `VideoGridController` accumulating stale clarity overrides: overrides of removed streams are now pruned, so long-running rooms no longer leak entries.
  - 修复 `VideoGridController` 累积失效清晰度覆盖的问题：已移除流的覆盖会被清理，长时间运行的房间不再泄漏条目。
- Fixed `switchCamera()` leaving a stale "camera active" status when the capture fails: the old device is already released, so the camera is now reported as off.
  - 修复采集失败时 `switchCamera()` 留下"摄像头已开启"失效状态的问题：旧采集设备已释放，现如实上报为已关闭。
- Fixed `switchToVariantStream()`: it now registers the replacement before dropping the old subscriber (never hands out a disposed object) and releases the new server resource when the session is disposed mid-switch.
  - 修复 `switchToVariantStream()`：先登记替代者再丢弃旧订阅器（绝不交出已销毁对象），并在切换期间会话被释放时清理新建的服务端资源。
- Fixed `RoleTransfer.handover()` leaving two anchors publishing at once: when revoking the previous anchor fails, the first grant is rolled back.
  - 修复 `RoleTransfer.handover()` 可能留下两个牵头同时推流的问题：收回原牵头失败时回滚第一次授权。
- Fixed LiveKit leaking a `Room` on every reconnect: the session now calls `room.dispose()` after `disconnect()`, so long-running sessions no longer accumulate rooms (a source of connection/handle leaks during 7×24 operation).
  - 修复 LiveKit 每次重连泄漏 `Room` 的问题：会话在 `disconnect()` 之后现在调用 `room.dispose()`，长时间运行的会话不再累积 Room（7×24 运行期间连接 / 句柄泄漏的来源之一）。
- Fixed `LiveKitPublisher` leaks and false "active" status: `dispose()` now releases the `ValueNotifier` (UI listeners no longer leak), and `startCamera` / `startMic` / `startScreenShare` no longer report the track as active when the room is not connected or permission is denied (they now report it off).
  - 修复 `LiveKitPublisher` 的泄漏与"已开启"假状态：`dispose()` 现在释放 `ValueNotifier`（UI 监听者不再泄漏）；房间未连或权限被拒时，`startCamera` / `startMic` / `startScreenShare` 不再谎报轨道已开启（现如实上报为关闭）。
- Fixed `Diagnostics` leaking a socket on a failed TLS handshake and aborting on one bad log line: the probe now destroys the underlying socket in `finally`, and crash-log parsing guards the type and skips corrupt lines instead of throwing.
  - 修复 `Diagnostics` 在 TLS 握手失败时泄漏 socket、且一条坏日志就中止整个诊断的问题：探测现在在 `finally` 销毁底层 socket，崩溃日志解析增加类型防护并跳过损坏行而非抛异常。
- Fixed `AppLifecycleGate` tearing the link down after the app returned to the foreground: lifecycle transitions are now serialised, so a rapid background→foreground toggle ends in the foreground.
  - 修复 `AppLifecycleGate` 在应用回到前台后错误拆除链路的问题：生命周期切换现已串行化，快速的"后台→前台"切换最终落在前台。
- Fixed `ControlLinkRouter` mislabeling a multi-path selection as `onlyOption`: when several reachable paths tie on RTT it now reports `lowestRtt` instead of falsely claiming there was only one path.
  - 修复 `ControlLinkRouter` 把多路径选择误标为 `onlyOption` 的问题：多条可达路径 RTT 恰好相等时，现改为上报 `lowestRtt`，而非谎称只有一条路径。

## 0.3.0

### Added / 新增

- Added a persistent BLE GATT teleop control channel: `BleTeleopChannel implements TeleopChannel` drops straight into `RobotController` / `DualTeleopChannel` (the watchdog, epoch gating and keepalive are unchanged; only the transport changes), `FlutterBluePlusBleLink` resolves the GATT service + command/telemetry characteristics, negotiates a larger MTU (256), subscribes to telemetry notifications and auto-reconnects on a drop (capped, exponential backoff), `BleTeleopDiscoverer` scans for the teleop GATT service while `BleDevice` keeps the public API free of `flutter_blue_plus` types (command/telemetry reuse the JSON envelopes of the other channels), and the example `ble_control_demo_page` plus the website docs (`ble_control.md` and its `zh/` counterpart) document the GATT contract.
  - 新增基于 BLE GATT 的持久遥操作控制通道：`BleTeleopChannel implements TeleopChannel` 可直接接入 `RobotController` / `DualTeleopChannel`（看门狗、epoch 门控与保活逻辑不变，仅传输层更换）；`FlutterBluePlusBleLink` 解析 GATT 服务与指令 / 遥测特征、协商更大 MTU（256）、订阅遥测通知并在断线后自动重连（有上限、指数退避）；`BleTeleopDiscoverer` 扫描遥操作 GATT 服务，`BleDevice` 让公开 API 不暴露 `flutter_blue_plus` 类型（指令 / 遥测复用其它通道的 JSON 封包）；示例 `ble_control_demo_page` 与文档站（`ble_control.md` 及其中文版）给出了 GATT 契约。
- Added protocol-agnostic BLE for any device (speaker, sensor, peripheral — not just robots): `BleScanner` discovers nearby devices with no service filter (or narrowed to `serviceUuids`) and returns the same `BleDevice` the teleop path uses, `BleGattClient` connects to a `BleDevice`, discovers services and exposes raw `read` / `write` / `subscribe` plus a `connectionState` stream with no teleop / ESP contract assumed, both are exported from the package root and built on `flutter_blue_plus` (keeping exactly one Bluetooth library in the dependency tree), and the example `ble_control_demo_page` adds a **Teleop / All devices** toggle where "All devices" connects via `BleGattClient` and shows the GATT services / characteristics (tap a readable characteristic to read it).
  - 新增面向任意设备（音响、传感器、外设——不限于机器人）的、与协议无关的通用 BLE：`BleScanner` 无需服务过滤即可发现附近设备（也可按 `serviceUuids` 收敛），返回与遥操作路径相同的 `BleDevice`；`BleGattClient` 连接 `BleDevice`、发现服务，并暴露原始的 `read` / `write` / `subscribe` 与 `connectionState` 流，不做任何遥操作 / ESP 契约假设；两者均从包根导出并基于 `flutter_blue_plus`，使依赖树中恰好只有一个蓝牙库；示例 `ble_control_demo_page` 新增 **Teleop / All devices** 切换，"All devices" 经 `BleGattClient` 连接并展示 GATT 服务 / 特征（点击可读取的特征即可读取值）。

## 0.2.0

### Added / 新增

- Added 4K (2160p) publish support: a new `ClarityLevel.p2160` (height 2160, label `2160p`, suggested full-layer cap 8000 kbps), LiveKit `capturePresetFor` / `simulcastLayersFor` now map `p2160` to `VideoParametersPresets.h2160_169` (capture 3840×2160 with 180p/540p/1080p/2160p simulcast layers), WHIP/WHEP publishers derive the 16:9 capture width from the clarity height so `p2160` automatically requests 3840×2160, the clarity selector in `RtcControlBar` and the example `rtc_demo_page` now offer `2160p`, and `fromHeight` maps 1080p < height ≤ 2160 to `p2160` with the `degradeClarity` ladder starting there.
  - 新增 4K（2160p）发布支持：新增 `ClarityLevel.p2160`（高度 2160、标签 `2160p`、满层建议码率上限 8000 kbps）；LiveKit 的 `capturePresetFor` / `simulcastLayersFor` 将 `p2160` 映射到 `VideoParametersPresets.h2160_169`（采集 3840×2160，simulcast 层为 180p/540p/1080p/2160p）；WHIP/WHEP 推流器按清晰度高度推导 16:9 采集宽度，`p2160` 自动请求 3840×2160；`RtcControlBar` 与示例 `rtc_demo_page` 的清晰度选择器现已提供 `2160p`；`fromHeight` 将 1080p < 高度 ≤ 2160 映射为 `p2160`，`degradeClarity` 阶梯也从该层起降。

### Fixed / 修复

- Fixed a negative bitrate after ICE restart / network handover: `RtcStatsSampler` compared the new peer connection's byte counter (which resets to ~0) against the previous cumulative baseline, producing a bogus negative `bitrateKbps` for one sample; the sampler now treats a counter reset as zero bitrate, `WhipWhepPublisher.restartIce()` resets both the video and audio samplers, and `RtcStatsSampler` accepts an injectable clock for deterministic tests.
  - 修复 ICE 重启 / 网络切换后的负码率：`RtcStatsSampler` 会把新 peer connection 的字节计数器（归零）与之前累计的基线比较，导致某一帧 `bitrateKbps` 出现虚假负值；现改为将计数器重置视为零码率，`WhipWhepPublisher.restartIce()` 会同时重置视频与音频采样器，`RtcStatsSampler` 也支持注入时钟以便确定性测试。

## 0.1.3

### Added / 新增

- Added `LocalPublisher.cameraStream` (a flutter_webrtc `MediaStream?`): exposes the camera media stream so consumers can render a local preview with a full `MediaStream` (binding only a track id does not render on Android); `WhipWhepPublisher` populates it from the active capture stream, while `LiveKitPublisher` returns `null` because LiveKit previews its own tracks via `lk.VideoTrackRenderer`.
  - 新增 `LocalPublisher.cameraStream`（`flutter_webrtc` 的 `MediaStream?`）：暴露摄像头媒体流，便于消费者用完整 `MediaStream` 渲染本地预览（只绑 track id 在 Android 上不会出画）；`WhipWhepPublisher` 从当前采集流填充该值，`LiveKitPublisher` 返回 `null`，因为 LiveKit 经自身的 `lk.VideoTrackRenderer` 渲染预览。

### Changed / 优化

- Raised the `permission_handler` constraint from `^11.0.0` to `^12.0.0`: 12.0.0 only requires Android `compileSdk 35` (its `permission_handler_android` submodule is 13.0.0), still ≤ the default Flutter template's 36, so the AGP 9.1.0 / compileSdk 36 build is unaffected and the plugin's own usage (`Permission`, `request()`, `status`, `openAppSettings()`) is unchanged.
  - 将 `permission_handler` 约束由 `^11.0.0` 提升到 `^12.0.0`：12.0.0 仅需 Android `compileSdk 35`（其 `permission_handler_android` 子模块为 13.0.0），仍 ≤ 默认 Flutter 模板的 36，因此 AGP 9.1.0 / compileSdk 36 构建不受影响，插件对其 Dart API（`Permission`、`request()`、`status`、`openAppSettings()`）的用法亦无变更。

## 0.1.2

### Fixed / 修复

- Fixed the example app's device-page action row overflowing on narrow screens: the SCAN BLE / DPP / NFC buttons were laid out in a fixed three-up `Row`; they now wrap to the next line when space is tight.
  - 修复示例应用设备页操作行在窄屏溢出的问题：SCAN BLE / DPP / NFC 原本排成固定三列 `Row`，现改为在空间不足时自动换行。
- Lowered the `permission_handler` constraint to `^11.0.0` so its Android submodule stays at API ≤ 36, keeping the default Flutter template (AGP 9.1.0 / compileSdk 36) buildable without forcing an AGP / Gradle upgrade.
  - 将 `permission_handler` 约束降到 `^11.0.0`，使其 Android 子模块停留在 API ≤ 36，从而默认 Flutter 模板（AGP 9.1.0 / compileSdk 36）无需升级 AGP / Gradle 即可构建。

## 0.1.1

### Fixed / 修复

- Fixed a joystick crash on first release: `_animation` was declared `late final` but reassigned in `_release()`, throwing `LateInitializationError`; it is now a reassignable `late` field.
  - 修复摇杆首次松手崩溃：`_animation` 被声明为 `late final` 却在 `_release()` 中二次赋值，抛 `LateInitializationError`；现改为可重新赋值的 `late` 字段。
- Fixed LiveKit multi-stream subscription revocation: subscribing a second stream overwrote the track-subscription allowlist and revoked the first; wanted track SIDs are now accumulated per participant and re-granted together.
  - 修复 LiveKit 多路订阅互相撤销：订阅第二路时覆盖轨道订阅白名单并撤销第一路；现按参与者累加想要的轨道 SID 并统一重新授权。
- Fixed `ResilientSession` re-entrant reconnect double scheduling: the `_recovering` guard was set after `await pause()`, letting two racing events each schedule a backoff timer; the guard is now taken synchronously before the await.
  - 修复 `ResilientSession` 重入重连双调度：`_recovering` 守卫在 `await pause()` 之后才置位，两个并发事件可同时穿过并各调度一个退避定时器；现改为在 await 前同步加锁。
- Fixed `ResilientSession` never emitting `RtcConnected`: the session's own `RtcConnected` was suppressed in `_onSessionEvent` but never re-emitted, so consumers never learned that a link was (re)established; it is now emitted from `_establish`.
  - 修复 `ResilientSession` 从不对外发出 `RtcConnected`：会话自身的该事件在 `_onSessionEvent` 中被抑制却从未补发，消费者永远收不到连接成功通知；现由 `_establish` 补发。
- Fixed `setBackground(false)` requesting a duplicate resume: when `autoResumeAfterReconnect` is enabled, `_afterReconnect` already resumed the gate, yet the foreground path asked for a second (orphaned) resume ticket; the foreground path now skips resume in that case.
  - 修复 `setBackground(false)` 重复恢复：开启 `autoResumeAfterReconnect` 时 `_afterReconnect` 已恢复门控，回到前台又发起一个被废弃的恢复票据；现已在该情况下跳过。
- Fixed a `LanDiscovery.discoverStream` early-cancel crash: `onCancel` touched `late` discovery / listener fields that were not initialized when the stream was cancelled before `startDiscovery` resolved, throwing `LateInitializationError`; they are now nullable with null checks.
  - 修复 `LanDiscovery.discoverStream` 提前取消崩溃：`onCancel` 访问尚未初始化的 `late` discovery / listener 字段（流在 `startDiscovery` 完成前被取消时），抛 `LateInitializationError`；现改为可空字段并加空判断。

## 0.1.0

### Added / 新增

- Initial release of `flutter_rtc_link`: a Flutter plugin for real-time audio/video and IoT device management with a dual-engine architecture (`WhipWhepEngine` over `flutter_webrtc`, `LiveKitEngine` over `livekit_client`) behind one unified abstraction (`RtcEngine` / `RtcSession` / `LocalPublisher` / `RemoteSubscriber`).
  - `flutter_rtc_link` 首个版本：实时音视频 + 物联网设备管理插件，双引擎架构（基于 `flutter_webrtc` 的 `WhipWhepEngine` 与基于 `livekit_client` 的 `LiveKitEngine`）统一抽象（`RtcEngine` / `RtcSession` / `LocalPublisher` / `RemoteSubscriber`）。
- Lead-operator publishing with simulcast: `startCamera` / `startMic` / `startScreenShare`, zero-renegotiation `switchCamera` via `replaceTrack` (RFC 9725 friendly), and `setPublishClarity` that caps only the top simulcast layer.
  - 牵头操作者推流（simulcast 多层）：`startCamera` / `startMic` / `startScreenShare`、经 `replaceTrack` 的零重协商 `switchCamera`（符合 RFC 9725），以及只限制最高层的 `setPublishClarity`。
- Subscription and picture switching: WHEP playback, per-stream `RemoteSubscriber.setClarity`, and a pure-Dart `VideoGridController` (main / pip / grid layouts, max visible, global clarity).
  - 订阅与画面切换：WHEP 拉流、每路独立的 `RemoteSubscriber.setClarity`，以及纯 Dart 的 `VideoGridController`（主画面 / 画中画 / 网格布局、最大可见数、全局清晰度）。
- Live relay: `RoleTransfer.promote` / `handover` (identity handover) and `StreamRelay.toRtmp` / `cascade` (server-side Egress or a secondary WHIP push).
  - 直播转接：`RoleTransfer.promote` / `handover`（身份交接）与 `StreamRelay.toRtmp` / `cascade`（服务端 Egress 或二次 WHIP 推流）。
- Robot teleoperation: `RobotController` with joystick velocity integration, PTZ, telemetry, a voice-intercom hookup, and a 500 ms watchdog that auto-stops the robot on command timeout or link loss.
  - 机器人遥操作：`RobotController` 支持摇杆速度积分、云台 PTZ、遥测、语音对讲接入，以及指令超时 / 断链 500ms 内自动停车的看门狗保护。
- IoT device management suite: multi-channel `DeviceProvisioning` (BLE → DPP/QR → NFC → SoftAP → SmartConfig strategy chain with automatic degradation), `OtaUpdater` (BLE/HTTP with SHA-256 verification), `DeviceLogCollector` (local cache + batch upload) and `Diagnostics` (WebRTC stats + network probe + device logs → JSON/Markdown report).
  - 物联网设备管理四件套：多通道 `DeviceProvisioning`（BLE → DPP/QR → NFC → SoftAP → SmartConfig 策略链，失败自动降级）、`OtaUpdater`（BLE/HTTP，SHA-256 校验）、`DeviceLogCollector`（本地缓存 + 批量补传）与 `Diagnostics`（WebRTC stats + 网络探测 + 设备日志 → JSON/Markdown 报告）。
- Unified permission gate `RtcPermissions.requestAll(capabilities)` covering the Android 13/14+ and iOS pitfalls (foreground-service microphone, nearby Wi-Fi devices, NFC entitlement); denials degrade features and emit `RtcEvent.permissionDenied` instead of crashing.
  - 统一权限入口 `RtcPermissions.requestAll(capabilities)`，覆盖 Android 13/14+ 与 iOS 的权限坑（前台服务麦克风、附近 Wi-Fi 设备、NFC entitlement）；权限被拒时功能降级并上报 `RtcEvent.permissionDenied`，不崩溃。
- Native modules: an Android DPP (Wi-Fi Easy Connect) platform channel and a microphone foreground service, plus an iOS Swift method-channel stub; channel prefix `pkg.flutter.dev/rtc_link/` with centralized `RtcErrorCodes`.
  - 原生模块：Android DPP（Wi-Fi Easy Connect）平台通道与麦克风前台服务，以及 iOS Swift method channel 桩；Method channel 前缀 `pkg.flutter.dev/rtc_link/`，错误码集中定义于 `RtcErrorCodes`。
- Ready-to-run example app (publish/subscribe, robot joystick, device management demos) and unit tests for the layout, clarity, relay, watchdog, provisioning, log-cache and diagnostics paths.
  - 可直接运行的 example 应用（推流 / 订阅、机器人摇杆、设备管理演示）以及布局、清晰度、转接、看门狗、配网、日志缓存与诊断路径的单元测试。
- Resilience layer for overseas / cross-public-network links: `ResilientSession` (supervised connect, jittered-backoff reconnect with automatic re-subscription), `RelayPlanner` (per-region TURN ordering plus `RelayMode.forced` escalation for CGNAT / cross-border paths), `NetworkPathMonitor` (Wi-Fi ↔ cellular handover → ICE restart) and `MediaHealthMonitor` (stutter / congestion / frozen-picture detection with keyframe → downgrade → re-subscribe recovery).
  - 面向海外 / 跨公网链路的韧性层：`ResilientSession`（受控建链、带抖动退避重连并自动重新订阅）、`RelayPlanner`（按区域排序 TURN + 面向 CGNAT / 跨境路径的 `RelayMode.forced` 升级）、`NetworkPathMonitor`（Wi-Fi ↔ 蜂窝切换触发 ICE 重启）与 `MediaHealthMonitor`（卡顿 / 拥塞 / 画面冻结检测，按请求关键帧 → 降档 → 重建订阅逐级恢复）。
- App-side pause/resume confirmation flow: `PauseResumeGate` stamps every operation with an epoch, pausing bumps the epoch so buffered operations are dropped instead of replayed, resuming is a two-step ticket handshake (`requestResume` → `confirmResume`) that expires, and `EpochOperationQueue` adds latest-wins buffering for teleoperation.
  - 应用侧暂停 / 恢复确认流程：`PauseResumeGate` 为每个操作盖上 epoch 戳，暂停会递增 epoch 使缓存操作被丢弃而非补发；恢复是一次会过期的两步票据握手（`requestResume` → `confirmResume`）；`EpochOperationQueue` 为遥操作提供"最新者胜"缓冲。
- Low-latency control link helpers: `ControlLinkRouter` (data channel preferred, MQTT fallback, latency budget), `ControlRttTracker` and `CommandRateLimiter`.
  - 低时延控制链路辅助：`ControlLinkRouter`（优先数据通道、回退 MQTT、带时延预算）、`ControlRttTracker` 与 `CommandRateLimiter`。
- `AppLifecycleGate`: maps Flutter lifecycle states (`paused` / `hidden` / `detached`) to background suspension and drives the pause/resume gate.
  - `AppLifecycleGate`：把 Flutter 生命周期状态（`paused` / `hidden` / `detached`）映射为后台挂起，并驱动暂停 / 恢复门控。

### Changed / 优化

- `RobotController` accepts an optional `PauseResumeGate` and `CommandRateLimiter`; `pause()` stops the robot immediately and invalidates every command issued before it, and the keepalive loop never replays a pre-pause velocity.
  - `RobotController` 可接收可选的 `PauseResumeGate` 与 `CommandRateLimiter`；`pause()` 立即停车并让此前所有指令失效，保活循环绝不补发暂停前的速度。
- `WhipWhepSession` implements `IceRestartable`: handover now rebuilds the peer connections with a fresh ICE configuration, because WHIP/WHEP forbids renegotiation (RFC 9725).
  - `WhipWhepSession` 实现了 `IceRestartable`：切换时用全新的 ICE 配置重建 peer connection，因为 WHIP/WHEP 不可重协商（RFC 9725）。
