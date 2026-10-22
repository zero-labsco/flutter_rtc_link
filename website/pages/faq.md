# FAQ

## Do I need a server?

Yes. The plugin is client-side only. For WHIP/WHEP use SRS, ZLMediaKit or
MediaMTX; for rooms use a LiveKit server. For anything custom, implement
`RtcSignaling` / `RtcSession`.

## Do I really need TURN?

For anything outside your own LAN: yes. Camera and robot NATs are frequently
symmetric or behind CGNAT, where STUN alone cannot punch through. `RelayPlanner`
will escalate to `RelayMode.forced` after `relayAfterAttempts` failed attempts.

## Why does clarity switching fail on my camera?

Because it publishes a single layer. There is no software clarity switch on a
single-layer stream. Either transcode server-side or publish main/sub streams as
separate stream ids (`_sd` / `_hd` / `_fhd`), which the plugin will switch
between (expect a 1–2 s blink).

## Why is my video frozen while the UI says "connected"?

ICE state is not media state. `MediaHealthMonitor` exists precisely for this: it
classifies `frozen` from stats and escalates to a keyframe request and then a
re-subscribe. Render `LinkPhase.degraded` as a warning, never as "connected".

## Why does the plugin rebuild the peer connection on a handover?

WHIP/WHEP (RFC 9725) forbids renegotiation after the initial SDP, so an ICE
restart is expressed as a fresh peer connection with a fresh ICE configuration.
Track changes never do this — they use `replaceTrack`.

## Why must I confirm a resume?

Because the alternative is dangerous. Commands captured before the interruption
(a joystick pushed left while the app was backgrounded) are no longer valid when
the link returns. `PauseResumeGate` bumps an epoch on every pause so those
operations are dropped, and requires an explicit confirmation to start a new
epoch.

## Can I disable the pause/resume flow?

You can pass no `gate` (legacy behaviour) or call
`resumeImmediately(afterReconnect: true)` in a custom policy. Both are explicit
opt-outs; neither is the default.

## Why is my BLE provisioning dependency different from the ESP docs?

`esp_provisioning_ble` pins `protobuf ^3`, which conflicts with
`livekit_client`'s `protobuf ^4/^6`. The plugin implements protocomm Security1
directly (`lib/src/device/protocomm.dart`) with `cryptography`, so no protobuf
dependency remains.

## iOS: can I use NFC tap-to-provision?

Read-only, and only with the entitlement
`com.apple.developer.nfc.readersession.formats` — which requires a paid account
and an explicit App ID (no wildcards). iOS cannot emulate tags (HCE).

## iOS: can the app connect to a device hotspot automatically?

No. Apple forbids programmatic Wi-Fi joining. Guide the user to Settings.

## Android 14: why does background audio crash?

Missing `FOREGROUND_SERVICE_MICROPHONE` and
`foregroundServiceType="microphone"`. Android throws `SecurityException` at
service start. The plugin ships `RtcLinkForegroundService` and merges the
declaration.

## Can I test on a simulator?

Only UI and logic. iOS Simulator has no camera, NFC or Bluetooth; the Android
emulator cannot do BLE, NFC or SoftAP. Device management needs real hardware.

## Where is the Chinese documentation?

Under [/zh](/zh).
