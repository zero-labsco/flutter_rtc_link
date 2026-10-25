# 推流

`LocalPublisher` 是两种引擎统一的推流入口。

```dart
final publisher = session.localPublisher!;
```

| 方法 | 说明 |
| --- | --- |
| `startCamera({facing, deviceId, maxClarity})` | 选择后置 / 前置 / 外接摄像头 |
| `startMic()` | 加入音频；静音是独立接口 |
| `startScreenShare({maxClarity})` | 屏幕 / 窗口采集 |
| `switchCamera({facing, deviceId})` | 只用 `replaceTrack`，**绝不重协商** |
| `setPublishClarity(level)` | 限制 **最高** simulcast 层 |
| `setMicEnabled(bool)` / `setCameraEnabled(bool)` | 静音 / 关画面而不拆会话 |

## 换采集源而不重协商

WHIP（RFC 9725）禁止在初始 SDP 之后修改 media section，因此插件从不重协商，
换轨一律用 `replaceTrack`：

```dart
await publisher.switchCamera(facing: CameraFacing.front); // 无 ICE、无 SDP
await publisher.startScreenShare();                        // 只创建一次 sender
await publisher.stopScreenShare();                         // 回到摄像头
```

:::tip
保持 sender 常驻、只换轨道。每次切换都新建/关闭 sender 正是 WHIP 服务端出现
"一秒黑屏"的原因。
:::

## Simulcast

服务端支持时，推流始终开启多层：

| `maxClarity` | 发布的层 |
| --- | --- |
| `p2160` | 2160p / 1080p / 540p |
| `p1080` | 1080p / 720p / 360p |
| `p720` | 720p / 360p |
| `p360` | 360p |

`setPublishClarity` 只升降**最高层**，低层始终保留，因此订阅端不会因为发布端的
选择而受限。

```dart
await publisher.setPublishClarity(ClarityLevel.p720); // 限制，不重启
```

## 码率与降级

把自适应交给服务端与带宽估计，只在 [`MediaHealthMonitor`](resilience) 报告持续
拥塞时才介入：

```dart
session.stats.listen((stats) {
  if (stats.packetLossPercent > 12) {
    unawaited(publisher.setPublishClarity(ClarityLevel.p360));
  }
});
```

## 结束

```dart
await publisher.stop();  // 停轨道，会话仍在
await session.leave();   // 彻底拆掉
```
