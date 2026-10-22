# Devices

## Provisioning

```dart
final ok = await DeviceProvisioning().provision(
  device,
  wifi: WifiCredential(ssid: ssid, password: password),
);
```

`ProvisionMethod.auto` runs a strategy chain and degrades automatically:

```
BLE → DPP / QR → NFC → SoftAP → SmartConfig
```

| Method | Transport | Platform notes |
| --- | --- | --- |
| BLE | protocomm Security1 (X25519 + AES-CTR) | Best UX, no Wi-Fi switching; self-implemented in `protocomm.dart` |
| DPP | QR / NFC out-of-band, WPA3 | Android 10+ only; custom platform channel |
| NFC | NDEF tag | Android read/write; iOS read-only + entitlement |
| SoftAP | Device hotspot + HTTP | Android full; iOS must ask the user to switch Wi-Fi manually |
| SmartConfig | Broadcast encoding | Last resort, poor compatibility |

```dart
provisioning.status.listen((s) {
  debugPrint('${s.method} → ${s.state} (${s.failureReason ?? 'ok'})');
});
```

:::tip
Never hardcode a PoP (Proof of Possession), SSID or password. They are always
supplied by the app or scanned from the device label.
:::

### Local discovery

```dart
final devices = await LanDiscovery().discover(type: '_rtc-link._tcp');
```

## OTA

```dart
OtaUpdater(channel: bleChannel)
    .upgrade(
      deviceId: device.id,
      firmwareUrl: signedUrl,
      expectedSha256: sha256,
    )
    .listen((p) => debugPrint('${p.percent} %'));
```

:::warning
Do not trust the device's "success" flag. Trust the **version it reports
afterwards**. The plugin keeps the update stream, retries, and leaves the
verdict to the reported version.
:::

Rollback is a device-side concern (dual partitions); the app only transfers the
image and displays state.

## Logs

```dart
final collector = DeviceLogCollector(
  uploader: HttpLogUploader(endpoint: 'https://api.example.com/logs'),
);
await collector.start(deviceId: device.id);
await collector.flush();   // offline batches are re-uploaded later
```

Sensitive values (`token`, `password`, `bearer`, `secret`) are redacted before
anything leaves the device.

## Diagnostics

```dart
final report = await Diagnostics.run(session: session);
final json = report.toJson();
final markdown = report.toMarkdown();
```

Aggregated: WebRTC stats (RTT / loss / fps / jitter), a network probe
(TURN / MQTT / HTTP reachability), device logs and provisioning/OTA history —
enough to tell "the network is broken" apart from "the device CPU is pegged".

## Permissions

```dart
final results = await RtcPermissions.requestAll(<RtcPermission>{
  RtcPermission.camera,
  RtcPermission.microphone,
  RtcPermission.nearbyWifiDevices,
});
```

Denials degrade the feature and emit `RtcEvent.permissionDenied`. The plugin
never crashes on a denial.
