# 设备管理

## 配网

```dart
final ok = await DeviceProvisioning().provision(
  device,
  wifi: WifiCredential(ssid: ssid, password: password),
);
```

`ProvisionMethod.auto` 按策略链执行并自动降级：

```
BLE → DPP / 扫码 → NFC → SoftAP → SmartConfig
```

| 方式 | 传输 | 平台说明 |
| --- | --- | --- |
| BLE | protocomm Security1（X25519 + AES-CTR） | 体验最好，无需切 Wi-Fi；插件自研于 `protocomm.dart` |
| DPP | 二维码 / NFC 带外，WPA3 | 仅 Android 10+；自建 platform channel |
| NFC | NDEF 标签 | Android 可读写；iOS 只读且需 entitlement |
| SoftAP | 设备热点 + HTTP | Android 完整；iOS 需引导用户手动切网 |
| SmartConfig | 广播包编码 | 最后兜底，兼容性差 |

```dart
provisioning.status.listen((s) {
  debugPrint('${s.method} → ${s.state}（${s.failureReason ?? '正常'}）');
});
```

:::tip
严禁硬编码 PoP（Proof of Possession）、SSID 或密码。它们一律由应用传入或从设备
标签扫码获得。
:::

### 局域网发现

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
不要相信设备返回的"成功"标志，相信它**随后上报的版本号**。插件只负责传输与状态
展示，判定交给版本号。
:::

回滚属于设备端职责（双分区），App 只负责传输与展示。

## 日志

```dart
final collector = DeviceLogCollector(
  uploader: HttpLogUploader(endpoint: 'https://api.example.com/logs'),
);
await collector.start(deviceId: device.id);
await collector.flush(); // 离线批次会在恢复后补传
```

`token` / `password` / `bearer` / `secret` 等敏感值在离机前即被脱敏。

## 诊断

```dart
final report = await Diagnostics.run(session: session);
final json = report.toJson();
final markdown = report.toMarkdown();
```

聚合内容：WebRTC stats（RTT / 丢包 / 帧率 / jitter）、网络探测（TURN / MQTT /
HTTP 可达性）、设备日志与配网 / OTA 历史——足以区分"网络坏了"与"设备 CPU 打满"。

## 权限

```dart
final results = await RtcPermissions.requestAll(<RtcPermission>{
  RtcPermission.camera,
  RtcPermission.microphone,
  RtcPermission.nearbyWifiDevices,
});
```

权限被拒时功能降级并上报 `RtcEvent.permissionDenied`，插件绝不崩溃。
