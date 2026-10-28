# Installation

## From pub.dev

```yaml
dependencies:
  flutter_rtc_link: ^__RTCLINK_VERSION__
```

```bash
flutter pub get
```

## From GitHub

```yaml
dependencies:
  flutter_rtc_link:
    git:
      url: https://github.com/zero-labsco/flutter_rtc_link.git
      ref: release/v__RTCLINK_VERSION__
```

## Import

```dart
import 'package:flutter_rtc_link/flutter_rtc_link.dart'; // media core
import 'package:flutter_rtc_link/flutter_rtc_link_device.dart'; // provisioning, OTA, logs
import 'package:flutter_rtc_link/flutter_rtc_link_robot.dart'; // teleoperation
```

Import only the modules you actually use: the media core, device management and
robot teleoperation are independent entry points. Everything public is
re-exported from one of these three files; never import `lib/src/...` directly.

## Requirements

| Requirement | Version |
| --- | --- |
| Flutter | >= 3.35.0 |
| Dart SDK | >= 3.9.0 < 4.0.0 |
| Android | `minSdk 24`, `compileSdk 36+` |
| iOS | 15.0+ |

## Android setup

The plugin merges these into the host manifest, so you normally add nothing:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission
    android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.hardware.nfc" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
```

:::warning
Android 14+ (API 34+) throws `SecurityException` at service start unless the
microphone foreground service is declared. The plugin ships
`RtcLinkForegroundService` for exactly this case.
:::

## iOS setup

Usage strings cannot be injected by the plugin — add every one you use to
`ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to publish video.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required to publish audio.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is used to provision and update devices.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Local network access is used to discover devices.</string>
<key>NFCReaderUsageDescription</key>
<string>NFC is used for tap-to-provision.</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

NFC additionally requires the entitlement
`com.apple.developer.nfc.readersession.formats` (paid account, explicit App ID).

## Next steps

- [Quick Start](quick-start)
- [Resilience](resilience) — required reading for public-internet deployments
