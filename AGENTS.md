# Flutter RTC Link - Agent Guide

This file defines the architecture, coding conventions, and required workflows
for the `flutter_rtc_link` Flutter plugin. AI coding agents (CodeBuddy, Trae,
Cursor, Claude Code, GitHub Copilot, Codex, etc.) should read and follow it for
any task in this repository. It is the single source of truth for project
conventions.

本文件定义 `flutter_rtc_link` Flutter 插件的架构、编码约定与必需工作流。AI 编码
智能体在本仓库执行任何任务前应阅读并遵循它；它是项目约定的唯一事实来源。

## Overview / 概览

`flutter_rtc_link` is a Flutter plugin for real-time audio/video (WebRTC) and
IoT device management: dual engines (WHIP/WHEP over `flutter_webrtc`, LiveKit
over `livekit_client`) behind one abstraction, plus device provisioning, OTA,
log collection, diagnostics, robot teleoperation, and a resilience layer for
overseas / cross-public-network links.

`flutter_rtc_link` 是实时音视频（WebRTC）与物联网设备管理插件：双引擎（基于
`flutter_webrtc` 的 WHIP/WHEP 与基于 `livekit_client` 的 LiveKit）统一抽象，
并提供设备配网、OTA、日志采集、诊断、机器人遥控，以及面向海外跨公网链路的韧性层。

## When to apply / 适用场景

- Implementing features, fixing bugs, or changing the public API in `lib/`.
- Touching the resilience layer (`lib/src/resilience/`) or the robot control
  path (`lib/src/robot/`).
- Opening pull requests (titles must follow Conventional Commits).
- Cutting a release or publishing to pub.dev.
- Editing `pubspec.yaml`, the workflows under `.github/workflows/`, or the
  native Android/iOS code.
- 在 `lib/` 中实现功能、修复缺陷或变更公开 API；
- 修改韧性层（`lib/src/resilience/`）或机器人控制路径（`lib/src/robot/`）；
- 发起 PR（标题必须遵循 Conventional Commits）；
- 发版或发布到 pub.dev；
- 修改 `pubspec.yaml`、`.github/workflows/` 下的工作流或 Android / iOS 原生代码。

## Architecture / 架构

- `lib/rtc_link.dart` — public barrel; re-export the public API only. Add new
  public symbols here. / 公开 barrel；只再导出公开 API，新增公开符号请加在此处。
- `lib/src/core/` — `rtc_engine` (dual-engine factory), `rtc_session`,
  `rtc_events` (sealed `RtcEvent` / `DeviceEvent`), `rtc_role`, `rtc_signaling`,
  `rtc_stats`.
- `lib/src/engines/` — `whip_whep_engine` (+ `whip_client`, `whep_subscriber`,
  `whip_whep_publisher`, `webrtc_stats_parser`) and `livekit_engine`
  (+ publisher/subscriber).
- `lib/src/resilience/` — `link_policy` (thresholds), `network_path`
  (handover detection), `relay_policy` (TURN planning, `IceRestartable`),
  `media_health` (stutter / congestion / freeze), `reconnect_supervisor`
  (jittered backoff), `link_events` (`LinkPhase`, `LinkHealth`, `ResumeTicket`,
  sealed `LinkEvent`), `pause_resume_gate` (epoch + `EpochOperationQueue`),
  `control_link` (router / RTT tracker / rate limiter), `resilient_session`
  (orchestrator), `app_lifecycle_gate`.
- `lib/src/publishers/`, `lib/src/subscribers/` — `LocalPublisher`,
  `RemoteSubscriber`, `VideoGridController`, `simulcast`.
- `lib/src/relay/` — `role_transfer` (promote / handover), `stream_relay`
  (RTMP / cascade).
- `lib/src/robot/` — `robot_controller` (watchdog + epoch gating),
  `teleop_channel` (MQTT / data channel / dual).
- `lib/src/device/` — `provisioning` (+ `provisioning_channels`, self-developed
  `protocomm` Security1), `ota_updater`, `log_collector`, `diagnostics`.
- `lib/src/platforms/` — `rtc_permissions`, `rtc_link_platform`,
  `lan_discovery`.
- `lib/src/widgets/` — `rtc_video_view`, `rtc_control_bar`, `joystick`.
- `website/` — Nextra 3 + Next.js 14 static docs site. English pages live in
  `website/pages/` (pure English), the Chinese counterparts in
  `website/pages/zh/` (pure Chinese). Never mix the two languages in one page.
  - `website/` —— Nextra 3 + Next.js 14 静态文档站。英文页面在
    `website/pages/`（纯英文），中文页面在 `website/pages/zh/`（纯中文）。
    同一页面内绝不混用两种语言。
- Native: Android
  `android/src/main/kotlin/com/zerolabsco/rtc_link/RtcLinkPlugin.kt`
  (+ `DppManager.kt`, `RtcLinkForegroundService.kt`); iOS
  `ios/flutter_rtc_link/Sources/flutter_rtc_link/RtcLinkPlugin.swift`. Keep
  native changes minimal and matching the method channel contract
  (`pkg.flutter.dev/rtc_link/`).
  - 原生：Android
    `android/src/main/kotlin/com/zerolabsco/rtc_link/RtcLinkPlugin.kt`
    （另有 `DppManager.kt`、`RtcLinkForegroundService.kt`）；iOS
    `ios/flutter_rtc_link/Sources/flutter_rtc_link/RtcLinkPlugin.swift`。原生
    改动保持最小并与 method channel 契约一致（`pkg.flutter.dev/rtc_link/`）。
- Consumers must never import `lib/src/` directly — everything public goes
  through the barrel. / 使用方绝不能直接导入 `lib/src/`，所有公开 API 都经 barrel。

## Dependencies and SDK constraints / 依赖与 SDK 约束

- Dart SDK: `>=3.9.0 <4.0.0`; Flutter: `>=3.35.0` (from `pubspec.yaml`).
- Runtime deps: `flutter_webrtc`, `livekit_client`, `mqtt_client`,
  `flutter_blue_plus`, `nfc_manager`, `ndef_record`, `nsd`, `wifi_iot`,
  `nordic_dfu`, `flutter_ota`, `permission_handler`, `cryptography`, `crypto`,
  `http`, `logging`.
- `livekit_client` must stay `>=2.4.9`: 2.4.x below that has an upstream
  null-safety bug in `local.dart` `negotiate()`.
  - `livekit_client` 必须保持在 `>=2.4.9`：更低的 2.4.x 在 `local.dart` 的
    `negotiate()` 中存在上游空安全缺陷。
- Do NOT reintroduce `esp_provisioning_ble`: it pins `protobuf ^3` and conflicts
  with LiveKit's `protobuf ^4/^6`. BLE provisioning uses the self-developed
  `lib/src/device/protocomm.dart`.
  - 不要重新引入 `esp_provisioning_ble`：它锁定 `protobuf ^3`，与 LiveKit 的
    `protobuf ^4/^6` 冲突。BLE 配网使用自研的 `lib/src/device/protocomm.dart`。
- License: MPL-2.0. Do not relicense without the maintainer's explicit decision.
  - 许可：MPL-2.0。未经维护者明确决定不得更换许可。

## Coding conventions / 编码约定

- Follow `effective_dart`; `flutter analyze` must report **No issues found**
  for `lib`, `test` and `example/lib`.
- **Identifiers are English-only; comments are bilingual (English first, then
  Chinese).** Doc comments follow `/// English. / 中文。` on two lines.
  - **标识符纯英文；注释英中双语（英文在前、中文在后）。**文档注释采用
    `/// English. / 中文。` 两行写法。
- All files use **LF** line endings — run `tool/normalize-eol.ps1` after adding
  files, and `dart format lib test example/lib tool` before committing.
  - 所有文件使用 **LF** 换行——新增文件后运行 `tool/normalize-eol.ps1`，提交前
    运行 `dart format lib test example/lib tool`。
- Use Conventional Commits for both commit messages AND PR titles: `feat:`,
  `fix:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`,
  `chore:`, `revert:`.
- Do not break the public API without a major version bump.
- The example app must contain **no hardcoded colors**: every color comes from
  `example/lib/theme/app_theme.dart` (`AppStatusColors` + one `brandSeed`).
  - 示例应用**不得出现硬编码颜色**：所有颜色来自
    `example/lib/theme/app_theme.dart`（`AppStatusColors` + 唯一的 `brandSeed`）。

## Non-negotiable behaviours / 不可协商的行为

These are safety-critical; do not "optimize" them away.
以下行为关乎安全，不得以"优化"为名改动。

1. **Robot watchdog**: any command timeout or refused send stops the robot
   immediately. / 指令超时或发送被拒时立即停车。
2. **No replay of expired operations**: every control operation carries an
   epoch from `PauseResumeGate`; anything stamped before a pause is dropped,
   never replayed after the resume. / 每个控制操作都带 epoch 戳；暂停前产生的
   操作在恢复后被丢弃，绝不补发。
3. **Three separated channels**: media (WebRTC), control (MQTT / DataChannel)
   and business (HTTPS) never mix; congestion degrades video first.
   / 媒体、控制、业务三条通道互不混用；拥塞时优先降级视频。
4. **Zero renegotiation on WHIP/WHEP** (RFC 9725): track changes are
   `replaceTrack`; ICE restart rebuilds the peer connection instead.
   / WHIP/WHEP（RFC 9725）零重协商：换轨用 `replaceTrack`，ICE 重启改为重建
   peer connection。
5. **Never trust a device-reported "OTA success"** — trust the version it
   reports afterwards. / 不轻信设备上报的"OTA 成功"，以其随后上报的版本号为准。
6. **Never hardcode credentials, tokens, SSIDs or POPs** — they are always
   supplied by the app. / 严禁硬编码凭证、令牌、SSID 或 POP，一律由应用传入。

## Workflows / 工作流

### Branching and PRs / 分支与 PR

- Branch from `main` with a typed prefix: `feat/`, `fix/`, `docs/`, `ci/`,
  `chore/`, etc.
- PR titles MUST follow Conventional Commits.

### Definition of done / 完成标准

```bash
dart format lib test example/lib tool
powershell -File tool/normalize-eol.ps1
flutter analyze lib test example/lib   # must be: No issues found!
flutter test                           # must be: All tests passed!
```

### Releasing / 发版

Bumping `pubspec.yaml`'s `version` is not done until every other version string
is in sync — the usual miss is the iOS native `s.version`, a README snippet, or
the CHANGELOG heading left at the old number. `pubspec.yaml`'s `version` is the
single source of truth.
/ 改 `pubspec.yaml` 的 `version` 不算完成，必须让其余版本串全部同步——最常漏的是
iOS 原生的 `s.version`、README 片段或仍停留在旧号的 CHANGELOG 标题。`pubspec.yaml`
的 `version` 是唯一事实来源。

Update all of these when the version changes / 改版本时必须同步以下全部：

- `pubspec.yaml` `version:` — the source of truth. / `pubspec.yaml` 的 `version:`（事实来源）。
- `example/pubspec.yaml` `version:` — mirror the plugin version. / `example/pubspec.yaml` 的 `version:`（与插件对齐）。
- `ios/flutter_rtc_link.podspec` `s.version = '<version>'` — the iOS native version shared by CocoaPods and SPM. / iOS 原生版本，CocoaPods 与 SPM 共用。
  - The SPM `Package.swift` has **no** version field (SPM versions come from the git tag), so there is nothing to bump there; the podspec `s.version` is the one that must move. / SPM 的 `Package.swift` **没有**版本字段（版本由 git tag 决定），那里没有要改的数字；podspec 的 `s.version` 才是必须同步处。
- `README.md` / `README_zh.md` — the `flutter_rtc_link: ^<version>` install snippet, the `ref: release/v<version>` git snippet, and the top `🔔 Upgrade recommended` / `🔔 推荐升级` callout (summarize what `<version>` changed and recommend upgrading; never reference prior versions). / 两份 README 的安装片段 `flutter_rtc_link: ^<version>`、git 片段 `ref: release/v<version>`，以及顶部 `🔔 推荐升级` callout（简述 `<version>` 的改动并建议升级，不引用旧版本）。
- `CHANGELOG.md` — a new `## <version>` section at the top. / 顶部新增 `## <version>` 条目。

Also review the docs for drift / 发版前还要审查文档内容是否需要更新：

- A version bump is only half the job — after the code changes, read the docs and
  confirm they still match: `README.md` / `README_zh.md` (feature list, usage
  snippets, API table) and the docs site (`website/pages`, `website/pages/zh`)
  must reflect the **current** public API and behavior.
  / 改版本只是发版的一半——改完代码后还要通读文档确认一致：`README.md` /
    `README_zh.md`（功能列表、用法示例、API 表）与文档站（`website/pages`、
    `website/pages/zh`）必须反映**当前**的公开 API 与行为。
- If a fix changed user-visible behavior, or an API was added / renamed /
  removed, the docs need an update too — not just the version strings. Doc drift
  is caught by a manual read, not by `tool/check_release.dart` (which only
  checks version numbers).
  / 若某次修复改变了用户可见行为，或新增/改名/删除了 API，文档也要同步更新——
    不只是版本号。`check_release.dart` 只校验版本串，文档漂移只能靠人工通读发现。

Verify with the bundled self-check before tagging / 打 tag 前用自带自检脚本验证：

```bash
dart run tool/check_release.dart   # non-zero exit if any version is stale
```

It treats `pubspec.yaml`'s `version` as truth and checks the podspec, both
READMEs and the CHANGELOG heading; wire it into CI to block a forgotten bump. It
intentionally ignores `Package.swift` and historical prose, and
`CONTRIBUTING.md`'s `v<version>` lines are illustrative only.
/ 脚本以 `pubspec.yaml` 的 `version` 为真值，核对 podspec、两份 README 与 CHANGELOG
标题；接进 CI 可拦截漏改。它有意忽略 `Package.swift` 与历史叙述，`CONTRIBUTING.md`
里的 `v<version>` 仅为示例。

### Testing conventions / 测试约定

- Tests live under `test/` mirroring `lib/src/` (`core/`, `device/`,
  `engines/`, `relay/`, `resilience/`, `robot/`, `subscribers/`).
- Broadcast `StreamController` events are delivered **asynchronously**: flush
  the event queue (`await Future<void>.delayed(...)`) before asserting.
  - 广播 `StreamController` 的事件是**异步**投递的：断言前需先冲刷事件队列。
- Use fake sessions/channels rather than touching real WebRTC in tests.
  - 测试中使用假会话 / 假通道，不要触碰真实 WebRTC。

### Documentation site / 文档站

```bash
cd website
npm ci
npm run dev        # local preview
node website/scripts/sync-docs.mjs --ci   # build into website/out/
```

- `README.md` is **English only**; `README_zh.md` is **Chinese only**. The same
  rule applies to the docs site: `pages/*.md` English, `pages/zh/*.md` Chinese.
  - `README.md` 仅英文；`README_zh.md` 仅中文。文档站同理：`pages/*.md` 为英文，
    `pages/zh/*.md` 为中文。
- `website/out/` is build output (gitignored); CI publishes it to `gh-pages`
  via `.github/workflows/docs.yml`. Never commit it.
  - `website/out/` 是构建产物（已 gitignore），由 CI 发布到 `gh-pages`
    分支（`.github/workflows/docs.yml`），绝不提交。
- The version shown on the site comes from `__RTCLINK_VERSION__`, replaced at
  build time from `pubspec.yaml`. Do not hardcode versions in pages.
  - 站点上的版本号来自 `__RTCLINK_VERSION__` 占位符，构建时由 `pubspec.yaml`
    注入；页面内不要硬编码版本。
