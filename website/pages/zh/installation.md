# 安装

## 从 pub.dev 安装

```yaml
dependencies:
  flutter_rtc_link: ^__RTCLINK_VERSION__
```

```bash
flutter pub get
```

## 从 GitHub 安装

```yaml
dependencies:
  flutter_rtc_link:
    git:
      url: https://github.com/zero-labsco/flutter_rtc_link.git
      ref: release/v__RTCLINK_VERSION__
```

## 导入

```dart
import 'package:flutter_rtc_link/flutter_rtc_link.dart'; // 媒体核心
import 'package:flutter_rtc_link/flutter_rtc_link_device.dart'; // 配网、OTA、日志
import 'package:flutter_rtc_link/flutter_rtc_link_robot.dart'; // 机器人遥控
```

按需导入所需模块即可：媒体核心、设备管理与机器人遥控是彼此独立的入口。所有公开
API 都由这三个文件之一再导出，**不要**直接导入 `lib/src/...`。

## 环境要求

| 要求 | 版本 |
| --- | --- |
| Flutter | >= 3.35.0 |
| Dart SDK | >= 3.9.0 < 4.0.0 |
| Android | `minSdk 24`，`compileSdk 36+` |
| iOS | 15.0+ |

## Android 配置

以下权限会由插件合并进宿主 manifest，通常无需手写：

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
Android 14+（API 34+）若未声明麦克风前台服务，启动服务时直接抛
`SecurityException`。插件已内置 `RtcLinkForegroundService` 覆盖该场景。
:::

## iOS 配置

用途字符串无法由插件注入，请按实际使用的能力逐条加到
`ios/Runner/Info.plist`：

```xml
<key>NSCameraUsageDescription</key>
<string>需要摄像头权限以推流。</string>
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限以推流。</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙权限以配网与升级设备。</string>
<key>NSLocalNetworkUsageDescription</key>
<string>需要本地网络权限以发现设备。</string>
<key>NFCReaderUsageDescription</key>
<string>需要 NFC 权限以碰一碰配网。</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

NFC 还需 entitlement `com.apple.developer.nfc.readersession.formats`
（付费账号 + 显式 App ID）。

## 下一步

- [快速开始](quick-start)
- [韧性](resilience) —— 部署到公网前必读
