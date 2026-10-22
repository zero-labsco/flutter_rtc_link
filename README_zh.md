# Flutter RTC Link

<div align="center" style="display: flex; align-items: center; justify-content: center; gap: 24px;">

<span style="font-size: 1.1em; padding: 0 8px;"><strong>简体中文</strong> &nbsp;|&nbsp; <a href="README.md">English</a></span>

</div>

一个 Flutter 插件同时搞定实时音视频（WebRTC）和物联网设备管理：用两套可任意切换的引擎推流 / 拉流，每条流都能单独调清晰度，并支持直播流转推；还能通过低延迟控制通道远程操控机器人，以及对设备做配网、固件升级与诊断。此外内置一层专为海外 / 跨公网弱网环境打造的韧性能力（自动重连、弱网恢复、中继切换等）。

[![pub version](https://img.shields.io/pub/v/flutter_rtc_link.svg)](https://pub.dev/packages/flutter_rtc_link)
[![pub points](https://img.shields.io/pub/points/flutter_rtc_link.svg)](https://pub.dev/packages/flutter_rtc_link/score)
[![CI](https://github.com/zero-labsco/flutter_rtc_link/actions/workflows/ci.yml/badge.svg)](https://github.com/zero-labsco/flutter_rtc_link/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-blue.svg)](https://github.com/zero-labsco/flutter_rtc_link/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green.svg)](https://pub.dev/packages/flutter_rtc_link)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%9C%93-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%E2%9C%93-0175C2?logo=dart)](https://dart.dev)
[![Style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://pub.dev/packages/effective_dart)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-4cc38a.svg)](https://zero-labsco.github.io/flutter_rtc_link/)

> **🔔 推荐升级：** `0.1.1` 修复了六个生命周期缺陷——摇杆首次松手崩溃、LiveKit 多路订阅互相撤销、`ResilientSession` 重连被重复调度、从不对外发出 `RtcConnected`、回到前台时重复恢复，以及局域网发现在流被提前取消时崩溃。建议所有用户升级到最新版本（`^0.1.1`）。

🌐 **[文档站](https://zero-labsco.github.io/flutter_rtc_link/)** &nbsp;·&nbsp; 📦 **[在 pub.dev 查看](https://pub.dev/packages/flutter_rtc_link)** &nbsp;·&nbsp; 🔗 **[查看 GitHub 仓库](https://github.com/zero-labsco/flutter_rtc_link)**

---

## 目录

- [功能特性](#功能特性)
- [安装](#安装)
- [使用](#使用)
  - [快速开始](#快速开始)
  - [推流](#推流)
  - [订阅](#订阅)
  - [韧性（海外、切网、弱网、后台）](#韧性海外切网弱网后台)
  - [机器人远控](#机器人远控)
  - [设备管理](#设备管理)
  - [权限](#权限)
- [API 参考](#api-参考)
- [示例](#示例)
- [测试](#测试)
- [文档](#文档)
- [贡献](#贡献)
- [许可](#许可)

---

## 功能特性

- **双引擎、统一抽象** —— 基于 `flutter_webrtc` 的 WHIP/WHEP 对接自建 SRS /
  ZLMediaKit / MediaMTX，基于 `livekit_client` 的 LiveKit 对接互动房间。换信令对象
  即可，其余代码零改动。
- **推流与 simulcast** —— `startCamera` / `startMic` / `startScreenShare`；
  `switchCamera` 走 `replaceTrack`（零重协商，符合 RFC 9725）；`setPublishClarity`
  只限制最高层。
- **订阅与清晰度切换** —— WHEP 拉流、按流 `setClarity`、纯 Dart 的
  `VideoGridController`（主讲 / 画中画 / 网格布局、最大可见数、全局清晰度）；
  没有变体流时明确上报而非假装能切。
- **直播转接** —— `RoleTransfer.promote` / `handover`（身份交接）与
  `StreamRelay.toRtmp` / `cascade`（服务端 Egress 或二次 WHIP 推流）。
- **机器人远控** —— 摇杆速度、独立通道的 PTZ、遥测、对讲接入，以及指令超时 / 发送
  被拒 / 断链时 500ms 内自动停车的看门狗。
- **物联网设备四件套** —— 多通道 `DeviceProvisioning`（BLE → DPP/QR → NFC →
  SoftAP → SmartConfig 自动降级）、`OtaUpdater`、`DeviceLogCollector`（本地缓存 +
  批量补传）与 `Diagnostics`（stats + 网络探测 + 日志 → JSON/Markdown）。
- **面向海外链路的韧性** —— 受控建链、带抖动退避的重连与自动重订阅、TURN 中继升级、
  Wi-Fi ↔ 蜂窝 ICE 重启、卡顿 / 拥塞 / 画面冻结自愈。
- **暂停 / 恢复确认** —— 每个操作都带 epoch 戳；暂停即失效，恢复是两步票据握手，
  中断前采集到的指令绝不会在恢复后被补发。
- **低时延控制链路** —— `ControlLinkRouter`（数据通道优先、MQTT 回退、带时延预算）、
  `ControlRttTracker`、`CommandRateLimiter`：先降视频，控制指令最后才受影响。
- **统一权限入口** —— `RtcPermissions.requestAll(...)` 覆盖 Android 13/14+ 与 iOS
  的各类坑；被拒时功能降级并上报 `RtcEvent.permissionDenied`，不崩溃。
- **该有原生就有原生** —— Android DPP（Wi-Fi Easy Connect）平台通道 + 麦克风前台
  服务；iOS Swift method channel 桩。
- **跨平台** —— Android 与 iOS。

---

## 安装

### 从 pub.dev 安装（推荐）

```yaml
dependencies:
  flutter_rtc_link: ^0.1.1
```

### 从 GitHub 安装

```yaml
dependencies:
  flutter_rtc_link:
    git:
      url: https://github.com/zero-labsco/flutter_rtc_link.git
      ref: release/v0.1.1   # 把 0.1.1 换成你需要的版本
```

### 平台配置

| 平台 | 要求 |
| --- | --- |
| Flutter | >= 3.35.0 |
| Dart SDK | >= 3.9.0 < 4.0.0 |
| Android | `minSdk 24`，`compileSdk 36+` |
| iOS | 15.0+ |

Android 权限由插件自动合并。iOS 的用途字符串无法由插件注入，请按需在
`ios/Runner/Info.plist` 添加 `NSCameraUsageDescription`、
`NSMicrophoneUsageDescription`、`NSBluetoothAlwaysUsageDescription`、
`NSLocalNetworkUsageDescription`、`NFCReaderUsageDescription` 与
`UIBackgroundModes: audio`。

### 导入

```dart
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
```

---

## 使用

### 快速开始

```dart
final engine = await RtcEngine.create(
  signaling: WhipWhepSignaling(
    whipUrl: 'https://srs.example.com/rtc/v1/whip/',
    whepUrl: 'https://srs.example.com/rtc/v1/whep/',
    // 跨公网必须部署 TURN。
    iceServers: <IceServer>[
      const IceServer(urls: 'stun:stun.example.com:3478'),
      IceServer(
        urls: 'turn:turn-ap.example.com:3478',
        username: await token.turnUser(),
        credential: await token.turnPass(),
      ),
    ],
  ),
);

final session = await engine.join(roomId: 'robot-42', role: RtcRole.robotOperator);
final remote = await session.subscribe(streamId: 'robot-42', quality: ClarityLevel.p720);
```

### 推流

```dart
final publisher = session.localPublisher!;
await publisher.startCamera(facing: CameraFacing.rear, maxClarity: ClarityLevel.p720);
await publisher.startMic();
await publisher.switchCamera(facing: CameraFacing.front); // replaceTrack，不重协商
await publisher.setPublishClarity(ClarityLevel.p360);     // 只限制最高层
```

### 订阅

```dart
await remote.setClarity(ClarityLevel.p540);   // 只影响这一路
final grid = VideoGridController()..addStream(stream);
grid.setMain('robot-42');
RtcVideoView(subscriber: remote);
```

:::note
单层码流没有软件清晰度切换能力。要么服务端转码，要么把主/子码流发布为不同 stream
id（`_sd` / `_hd` / `_fhd`）——插件会在其间切换（1~2s 闪断），否则上报
`claritySwitchUnsupported`。
:::

### 韧性（海外、切网、弱网、后台）

```dart
final monitor = CallbackNetworkMonitor(); // 由 connectivity_plus 喂数据
final resilient = await ResilientSession.connect(
  roomId: 'robot-42',
  role: RtcRole.robotOperator,
  factory: engine.join,
  config: ResilientSessionConfig(
    policy: const LinkPolicy(
      connectTimeout: Duration(seconds: 12),
      reconnect: ReconnectPolicy(maxAttempts: 8, relayAfterAttempts: 2),
      restartIceOnHandover: true,
    ),
    relay: RelayPlanner(servers: iceServers, preferredRegions: <String>['ap']),
    monitor: monitor,
  ),
);

await resilient.setBackground(true);   // 暂停操作并关闭视频轨道
await resilient.setBackground(false);  // 签发恢复票据
await resilient.confirmResume();       // 操作者确认 → 新 epoch
```

| 关注点 | 实现 |
| --- | --- |
| 连接建立 | `LinkPolicy.connectTimeout` + 受控重试 |
| 中继 / TURN | `RelayPlanner` 按区域排序，`relayModeForAttempt` → `iceTransportPolicy: relay` |
| 网络切换 | `NetworkPathMonitor`（类型 + 代次）→ `IceRestartable.restartIce` |
| 弱网 | `MediaHealthMonitor`：卡顿 / 拥塞 / 冻结 → 关键帧 → 降档 → 重建订阅 |
| 后台 | `AppLifecycleGate` → `setBackground` 应用 `BackgroundPolicy` |
| 断线重连 | 带抖动退避，恢复后重新订阅每一路记住的流 |
| 过期操作 | `PauseResumeGate` 的 epoch 戳 + 两步恢复票据 |

```dart
final gate = PauseResumeGate();
final queue = EpochOperationQueue<Velocity>(gate);

queue.submit(const Velocity(linear: 0.6)); // epoch 1
gate.pause(PauseReason.background);        // epoch 2：此前一切过期

final ticket = gate.requestResume();       // 绑定 epoch 3，会过期
if (gate.confirmResume(ticket)) {
  queue.take();                            // null → 已丢弃，不是补发
}
```

### 机器人远控

```dart
final robot = RobotController(channel: mqttChannel, gate: gate);
await robot.connect(deviceId: 'robot-42');
await robot.move(velocityFromJoystick(dx: 0.4, dy: -0.8));
await robot.setPtz(pan: 30, tilt: -10);

await robot.pause(PauseReason.background);        // 停车 + 让旧指令失效
final ticket = robot.requestResume();             // 需操作者确认
await robot.confirmResume(ticket);
```

### 设备管理

```dart
await DeviceProvisioning().provision(
  device,
  wifi: WifiCredential(ssid: ssid, password: password),
);

OtaUpdater(channel: bleChannel).upgrade(
  deviceId: device.id,
  firmwareUrl: signedUrl,
  expectedSha256: sha256,
).listen((p) => debugPrint('${p.percent} %'));

await DeviceLogCollector().flush();
final report = await Diagnostics.run(session: session);
```

### 权限

```dart
final results = await RtcPermissions.requestAll(<RtcPermission>{
  RtcPermission.camera,
  RtcPermission.microphone,
  RtcPermission.nearbyWifiDevices,
});
```

---

## API 参考

| 入口 | 用途 |
| --- | --- |
| `RtcEngine.create(signaling:)` | 按信令对象创建对应引擎 |
| `RtcSession` | `join` / `subscribe` / `unsubscribe` / `leave` / `events` / `stats` |
| `LocalPublisher` | `startCamera` / `startMic` / `startScreenShare` / `switchCamera` / `setPublishClarity` |
| `RemoteSubscriber` | `setClarity` / `clarity` 通知器 / `videoRenderer` |
| `VideoGridController` | 纯 Dart 的布局与清晰度编排 |
| `RoleTransfer` / `StreamRelay` | 身份交接与媒体转发 |
| `RobotController` | `move` / `setPtz` / `stop` / `pause` / `requestResume` / `confirmResume` |
| `ResilientSession` | `connect` / `setBackground` / `confirmResume` / `resubscribe` / `restartIce` |
| `PauseResumeGate` / `EpochOperationQueue<T>` | epoch 管控与"最新者胜"缓冲 |
| `RelayPlanner` / `NetworkPathMonitor` / `MediaHealthMonitor` | 中继、切换与弱网检测 |
| `ControlLinkRouter` / `ControlRttTracker` / `CommandRateLimiter` | 低时延控制路径 |
| `DeviceProvisioning` / `OtaUpdater` / `DeviceLogCollector` / `Diagnostics` | 物联网设备四件套 |
| `RtcPermissions` | 一次性能力申请 |

---

## 示例

```bash
cd example && flutter run
```

五个标签页：`link`（推流 / 订阅）、`robot`（摇杆 + 看门狗）、`device`（配网 /
升级 / 日志）、`diag`（诊断报告）与 `resil`（韧性实验室：暂停恢复确认、切换、
弱网、退避）。

---

## 测试

```bash
flutter analyze lib test example/lib
flutter test
```

---

## 文档

文档站位于 [`website/`](website)（Nextra 3 + Next.js 14）并发布到 GitHub Pages：
安装、快速开始、推流、订阅、韧性、机器人远控、设备管理与常见问题，每篇都有 `/zh/`
下的中文版。

```bash
cd website && npm ci && npm run dev
```

---

## 贡献

欢迎贡献！提交 issue 或 PR 前请先阅读[贡献指南](CONTRIBUTING.md)。

- 🐛 [报告缺陷](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=bug_report.md)
- 💡 [功能建议](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=feature_request.md)
- 💬 [参与讨论](https://github.com/zero-labsco/flutter_rtc_link/discussions)
- 📖 [贡献指南](CONTRIBUTING.md)

---

## 许可

Copyright (c) 2026 Zero Labs Co. (AmisKwok)。本项目采用 **Mozilla Public
License 2.0（MPL-2.0）** 许可——详见 [LICENSE](LICENSE) 文件。版权声明与附加条款
（无担保、不背书）见 [NOTICE](NOTICE)。

- **允许商业使用。** 允许使用、修改与闭源分发。
- **修改了插件？** 你修改过的文件必须以源码形式按 MPL-2.0 发布，但你自己的应用
  **无需**开源。
- **原样使用？** 无需公开源码。
- **不背书。** 未经事先书面许可，不得以 "Zero Labs Co."、"flutter_rtc_link"、
  项目 logo / 吉祥物形象及作者姓名（AmisKwok）为衍生品背书、推广或暗示赞助与
  从属关系。
- **无担保、无责任。** 版权持有人对任何修改版或衍生版本不提供担保、不承担任何责任；
  修改版本必须明确标注为已修改。

本插件按"原样"提供，不附带任何形式的担保。对于修改版本或衍生项目的功能、安全性
及使用后果，作者不承担任何责任。
