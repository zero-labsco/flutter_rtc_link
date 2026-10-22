---
title: Flutter RTC Link
---

# Flutter RTC Link

Real-time audio/video (WebRTC) and IoT device management in one Flutter plugin:
publish and subscribe with two interchangeable engines, switch clarity per
stream, relay a live stream, teleoperate a robot over a low-latency control
link, provision / update / diagnose devices — plus a resilience layer built for
overseas, cross-public-network links.

Version: **__RTCLINK_VERSION__** · License: MPL-2.0 · Platforms: Android, iOS

---

## Three channels, never mixed

```
media    WebRTC (WHIP/WHEP or LiveKit)   video / audio / screen
control  MQTT or DataChannel             teleoperation, PTZ, telemetry, device signaling
business HTTPS                           tokens, device binding, OTA distribution, reports
```

Each channel degrades independently. When the network degrades, video goes
first, audio second, control commands last.

---

## Two engines, one abstraction

| | WHIP/WHEP engine | LiveKit engine |
| --- | --- | --- |
| Backing package | `flutter_webrtc` | `livekit_client` |
| Best for | Self-hosted SRS / ZLMediaKit / MediaMTX, IoT camera playback | Interactive rooms, co-hosting, large audiences |
| Signaling | HTTP (RFC 9725) | LiveKit server + JWT |
| Renegotiation | Forbidden — use `replaceTrack`, rebuild on ICE restart | Allowed |

Both expose the same surface: `RtcEngine` → `RtcSession` → `LocalPublisher` /
`RemoteSubscriber`, plus a shared `RtcEvent` stream and `RtcStats`.

---

## What is in the box

| Area | Entry point |
| --- | --- |
| Publishing (camera / mic / screen, simulcast) | `LocalPublisher` |
| Subscribing and clarity switching | `RemoteSubscriber`, `VideoGridController` |
| Live relay and role transfer | `RoleTransfer`, `StreamRelay` |
| Robot teleoperation | `RobotController`, `TeleopChannel` |
| Device provisioning, OTA, logs, diagnostics | `DeviceProvisioning`, `OtaUpdater`, `DeviceLogCollector`, `Diagnostics` |
| Permissions | `RtcPermissions` |
| **Resilience (overseas, handover, weak network, background)** | `ResilientSession`, `RelayPlanner`, `NetworkPathMonitor`, `MediaHealthMonitor`, `PauseResumeGate` |

---

## Start here

- [Installation](installation) — add the dependency and the platform setup.
- [Quick Start](quick-start) — your first publish/subscribe loop.
- [Resilience](resilience) — **read this before shipping outside a LAN.**
- [Robot Teleoperation](robot) — joystick, watchdog and the pause/resume flow.
- [Devices](devices) — provisioning, OTA, logs, diagnostics.
- [FAQ](faq) — common questions and platform caveats.

Chinese documentation lives under [/zh](/zh).
