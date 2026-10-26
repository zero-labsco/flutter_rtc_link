# Flutter RTC Link

<div align="center" style="display: flex; align-items: center; justify-content: center; gap: 24px;">

<span style="font-size: 1.1em; padding: 0 8px;"><strong>English</strong> &nbsp;|&nbsp; <a href="README_zh.md">简体中文</a></span>

</div>

Real-time audio/video (WebRTC) and IoT device management in one Flutter plugin: publish and subscribe with two interchangeable engines, switch clarity per stream, relay a live stream, teleoperate a robot over a low-latency control link, provision / update / diagnose devices — plus a resilience layer built for overseas, cross-public-network links.

[![pub version](https://img.shields.io/pub/v/flutter_rtc_link.svg)](https://pub.dev/packages/flutter_rtc_link)
[![pub points](https://img.shields.io/pub/points/flutter_rtc_link.svg)](https://pub.dev/packages/flutter_rtc_link/score)
[![CI](https://github.com/zero-labsco/flutter_rtc_link/actions/workflows/ci.yml/badge.svg)](https://github.com/zero-labsco/flutter_rtc_link/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-blue.svg)](https://github.com/zero-labsco/flutter_rtc_link/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green.svg)](https://pub.dev/packages/flutter_rtc_link)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%9C%93-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%E2%9C%93-0175C2?logo=dart)](https://dart.dev)
[![Style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://pub.dev/packages/effective_dart)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-4cc38a.svg)](https://zero-labsco.github.io/flutter_rtc_link/)

> **🔔 Upgrade recommended:** `0.3.1` hardens teardown, link policy and provisioning semantics — it fixes leaks, crashes and protocol bugs across WebRTC, BLE, MQTT, OTA and provisioning (see CHANGELOG). The **persistent BLE GATT teleop control channel** from `0.3.0` is unchanged: `BleTeleopChannel` implements `TeleopChannel`, drops into `RobotController` / `DualTeleopChannel`, auto-reconnects on a drop, and ships with `BleTeleopDiscoverer`. All users should upgrade to the latest version (`^0.3.1`).

🌐 **[Documentation](https://zero-labsco.github.io/flutter_rtc_link/)** &nbsp;·&nbsp; 📦 **[View on pub.dev](https://pub.dev/packages/flutter_rtc_link)** &nbsp;·&nbsp; 🔗 **[View on GitHub](https://github.com/zero-labsco/flutter_rtc_link)**

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Quick Start](#quick-start)
  - [Publishing](#publishing)
  - [Subscribing](#subscribing)
  - [Resilience (Overseas, Handover, Weak Network, Background)](#resilience-overseas-handover-weak-network-background)
  - [Robot Teleoperation](#robot-teleoperation)
  - [Devices](#devices)
  - [Permissions](#permissions)
- [API Reference](#api-reference)
- [Example](#example)
- [Testing](#testing)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Dual Engines, One Abstraction** — WHIP/WHEP over `flutter_webrtc` for self-hosted SRS / ZLMediaKit / MediaMTX, LiveKit over `livekit_client` for interactive rooms. Swap the signaling object, keep every other line of code.
- **Publishing with Simulcast** — `startCamera` / `startMic` / `startScreenShare`, `switchCamera` via `replaceTrack` (zero renegotiation, RFC 9725-friendly), and `setPublishClarity` that only caps the top layer.
- **Subscribing and Clarity Switching** — WHEP playback, per-stream `setClarity`, pure-Dart `VideoGridController` (speaker / pip / grid layouts, max visible, global clarity), and honest failure when a stream has no variant to switch to.
- **Live Relay** — `RoleTransfer.promote` / `handover` (identity handover) and `StreamRelay.toRtmp` / `cascade` (server-side Egress or a secondary WHIP push).
- **Robot Teleoperation** — joystick velocity, PTZ on its own channel, telemetry, intercom hookup, a 500 ms watchdog (stops on command timeout, refused sends or link loss), and a BLE GATT control channel (`BleTeleopChannel`) for direct, network-free teleoperation.
- **Generic BLE for Any Device** — `BleScanner` discovers any nearby BLE device and `BleGattClient` connects, discovers GATT services and exposes raw `read` / `write` / `subscribe` — no robot or ESP contract assumed, so speaker / sensor / peripheral projects can use the plugin's BLE stack too. Built on `flutter_blue_plus`, so the dependency tree keeps exactly one Bluetooth library.
- **IoT Device Suite** — multi-channel `DeviceProvisioning` (BLE → DPP/QR → NFC → SoftAP → SmartConfig, auto-degrading), `OtaUpdater`, `DeviceLogCollector` (local cache + batch re-upload) and `Diagnostics` (stats + network probe + logs → JSON/Markdown).
- **Resilience for Overseas Links** — supervised connect, jittered backoff reconnect with automatic re-subscription, TURN relay escalation, Wi-Fi ↔ cellular ICE restart, stutter / congestion / frozen-picture recovery.
- **Pause / Resume Confirmation** — every operation carries an epoch; pausing invalidates it, and resuming is a two-step ticket handshake, so no command captured before an interruption is ever replayed after it.
- **Low-Latency Control Link** — `ControlLinkRouter` (data channel preferred, MQTT fallback, latency budget), `ControlRttTracker`, `CommandRateLimiter`: video degrades first, control commands survive.
- **Unified Permissions** — `RtcPermissions.requestAll(...)` covering the Android 13/14+ and iOS pitfalls; denials degrade features and emit `RtcEvent.permissionDenied` instead of crashing.
- **Native Where It Matters** — Android DPP (Wi-Fi Easy Connect) platform channel plus a microphone foreground service; iOS Swift method-channel stub.
- **Cross-Platform** — Android and iOS.

---

## Installation

### Pub.dev (Recommended)

```yaml
dependencies:
  flutter_rtc_link: ^0.3.1
```

### GitHub

```yaml
dependencies:
  flutter_rtc_link:
    git:
      url: https://github.com/zero-labsco/flutter_rtc_link.git
      ref: release/v0.3.1   # replace with the version you need
```

### Platform Setup

| Platform | Requirement |
| --- | --- |
| Flutter | >= 3.35.0 |
| Dart SDK | >= 3.9.0 < 4.0.0 |
| Android | `minSdk 24`, `compileSdk 36+` |
| iOS | 15.0+ |

Android permissions are merged by the plugin. iOS usage strings cannot be injected — add `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NFCReaderUsageDescription` and `UIBackgroundModes: audio` to `ios/Runner/Info.plist` as needed.

### Import

```dart
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
```

---

## Usage

### Quick Start

```dart
final engine = await RtcEngine.create(
  signaling: WhipWhepSignaling(
    whipUrl: 'https://srs.example.com/rtc/v1/whip/',
    whepUrl: 'https://srs.example.com/rtc/v1/whep/',
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

### Publishing

```dart
final publisher = session.localPublisher!;
await publisher.startCamera(facing: CameraFacing.rear, maxClarity: ClarityLevel.p720);
await publisher.startMic();
await publisher.switchCamera(facing: CameraFacing.front); // replaceTrack, no renegotiation
await publisher.setPublishClarity(ClarityLevel.p360);     // caps the top layer only
```

### Subscribing

```dart
await remote.setClarity(ClarityLevel.p540);   // this stream only
final grid = VideoGridController()..addStream(stream);
grid.setMain('robot-42');
RtcVideoView(subscriber: remote);
```

:::note
A single-layer stream has no software clarity switch. Either transcode server-side, or publish main/sub streams as separate stream ids (`_sd` / `_hd` / `_fhd`) — the plugin will switch between them (1–2 s blink) and reports `claritySwitchUnsupported` otherwise.
:::

### Resilience (Overseas, Handover, Weak Network, Background)

```dart
final monitor = CallbackNetworkMonitor(); // wired to connectivity_plus
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

await resilient.setBackground(true);   // pauses operations, drops the video track
await resilient.setBackground(false);  // issues a resume ticket
await resilient.confirmResume();       // the operator confirms → new epoch
```

| Concern | Implementation |
| --- | --- |
| Connection establishment | `LinkPolicy.connectTimeout` + supervised retries |
| Relay / TURN | `RelayPlanner` per-region ordering, `relayModeForAttempt` → `iceTransportPolicy: relay` |
| Network switching | `NetworkPathMonitor` (kind + generation) → `IceRestartable.restartIce` |
| Weak network | `MediaHealthMonitor`: stutter / congestion / frozen → keyframe → downgrade → re-subscribe |
| Background | `AppLifecycleGate` → `setBackground` applies `BackgroundPolicy` |
| Reconnect | Jittered backoff, re-subscribes every remembered stream |
| Stale operations | `PauseResumeGate` epoch stamps + two-step resume ticket |

```dart
final gate = PauseResumeGate();
final queue = EpochOperationQueue<Velocity>(gate);

queue.submit(const Velocity(linear: 0.6)); // epoch 1
gate.pause(PauseReason.background);        // epoch 2 — everything before is stale

final ticket = gate.requestResume();       // bound to epoch 3, expires
if (gate.confirmResume(ticket)) {
  queue.take();                            // null → dropped, NOT replayed
}
```

### Robot Teleoperation

```dart
final robot = RobotController(channel: mqttChannel, gate: gate);
await robot.connect(deviceId: 'robot-42');
await robot.move(velocityFromJoystick(dx: 0.4, dy: -0.8));
await robot.setPtz(pan: 30, tilt: -10);

await robot.pause(PauseReason.background);        // stop + invalidate everything
final ticket = robot.requestResume();             // operator must confirm
await robot.confirmResume(ticket);
```

Any `TeleopChannel` works here — `MqttTeleopChannel` (cloud broker), `DataChannelTeleopChannel` (WebRTC, lowest latency), or the new `BleTeleopChannel.forDevice(device)` for a persistent BLE GATT link. Wrap two in `DualTeleopChannel(primary, secondary)` so control still survives a network drop (e.g. network primary, BLE secondary).

### Devices

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

### Permissions

```dart
final results = await RtcPermissions.requestAll(<RtcPermission>{
  RtcPermission.camera,
  RtcPermission.microphone,
  RtcPermission.nearbyWifiDevices,
});
```

---

## API Reference

| Entry point | Purpose |
| --- | --- |
| `RtcEngine.create(signaling:)` | Creates the engine matching the signaling object |
| `RtcSession` | `join` / `subscribe` / `unsubscribe` / `leave` / `events` / `stats` |
| `LocalPublisher` | `startCamera` / `startMic` / `startScreenShare` / `switchCamera` / `setPublishClarity` |
| `RemoteSubscriber` | `setClarity` / `clarity` notifier / `videoRenderer` |
| `VideoGridController` | Pure-Dart layout and clarity orchestration |
| `RoleTransfer` / `StreamRelay` | Identity handover and media forwarding |
| `RobotController` | `move` / `setPtz` / `stop` / `pause` / `requestResume` / `confirmResume` |
| `BleTeleopChannel` / `BleTeleopDiscoverer` | Persistent BLE GATT teleop channel and device scanner |
| `ResilientSession` | `connect` / `setBackground` / `confirmResume` / `resubscribe` / `restartIce` |
| `PauseResumeGate` / `EpochOperationQueue<T>` | Epoch discipline and latest-wins buffering |
| `RelayPlanner` / `NetworkPathMonitor` / `MediaHealthMonitor` | Relay, handover and weak-network detection |
| `ControlLinkRouter` / `ControlRttTracker` / `CommandRateLimiter` | Low-latency control path |
| `DeviceProvisioning` / `OtaUpdater` / `DeviceLogCollector` / `Diagnostics` | IoT device suite |
| `RtcPermissions` | One-shot capability requests |

---

## Example

```bash
cd example && flutter run
```

Six tabs: `link` (publish/subscribe), `robot` (joystick + watchdog), `device` (provisioning/OTA/logs), `ble` (BLE GATT teleop: scan/connect/joystick), `diag` (diagnostics report) and `resil` (resilience lab: pause/resume confirmation, handover, weak network, backoff).

---

## Testing

```bash
flutter analyze lib test example/lib
flutter test
```

---

## Documentation

The documentation site lives in [`website/`](website) (Nextra 3 + Next.js 14) and is published to GitHub Pages: **Installation**, **Quick Start**, **Publishing**, **Subscribing**, **Resilience**, **BLE Teleop Control**, **Robot Teleoperation**, **Devices** and **FAQ** — each with a Chinese counterpart under `/zh/`.

```bash
cd website && npm ci && npm run dev
```

---

## Contributing

Contributions are welcome! Please read the [Contributing Guidelines](CONTRIBUTING.md) before submitting issues or pull requests.

- 🐛 [Report a Bug](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=bug_report.md)
- 💡 [Request a Feature](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=feature_request.md)
- 💬 [Join Discussions](https://github.com/zero-labsco/flutter_rtc_link/discussions)
- 📖 [Contributing Guide](CONTRIBUTING.md)

---

## License

Copyright (c) 2026 Zero Labs Co. (AmisKwok). This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)** — see the [LICENSE](LICENSE) file for details. The copyright notice and additional statements (no warranty, no endorsement) live in [NOTICE](NOTICE).

- **Commercial use is allowed.** Use, modification and closed-source distribution are permitted.
- **Modified the plugin?** The files you modified must be published in source form under MPL-2.0. Your own app does **not** need to be open-sourced.
- **Used it unmodified?** No source disclosure is required.
- **No endorsement.** "Zero Labs Co.", "flutter_rtc_link", the logo / mascot artwork, and the author's name (AmisKwok) may not be used to endorse or promote derived products, or to imply sponsorship or affiliation, without prior written permission.
- **No warranty, no liability.** The copyright holder provides no warranty and accepts no liability for any modified or derivative version; modified versions must be clearly marked as modified.

This plugin is provided "as is", without warranty of any kind. The author assumes no responsibility or liability for the functionality, security, or any consequences arising from the use of modified versions or derivative projects.
