# 订阅

```dart
final remote = await session.subscribe(
  streamId: 'robot-42',
  quality: ClarityLevel.p720,
);
```

一个 `RemoteSubscriber` 对应一路流：各自持有 `clarity`（`ValueNotifier`）、
渲染器与 stats 流。

## 切换清晰度

```dart
await remote.setClarity(ClarityLevel.p540); // 只影响这一路
await session.unsubscribe('robot-42');
```

| 引擎 | 单层流 | 多层 / 变体流 |
| --- | --- | --- |
| LiveKit | `videoQuality` 直接映射 | 原生选层 |
| WHIP/WHEP | **无法软切换**——插件改为切换变体流 id（`_sd` / `_hd` / `_fhd`，1~2s 闪断）或上报 `claritySwitchUnsupported` | SDP `rid` 选层 |

:::warning
单层流没有软件清晰度切换能力。要么在服务端转码（ZLMediaKit），要么把主/子码流
暴露为不同 stream id——插件绝不会假装能切。
:::

## auto 模式

`auto` 跟随 `RtcStats`：可用带宽、丢包与 RTT 共同决定升降层，而
`remote.clarity.value` 始终反映**当前实际**档位，UI 不会说谎。

## 布局

`VideoGridController` 是纯 Dart，不依赖 widget 与引擎：

```dart
final grid = VideoGridController();
grid.addStream(stream);
grid.setMain('robot-42');                  // 主画面 / 画中画 / 网格
grid.setGlobalClarity(ClarityLevel.p360);
final visible = grid.visibleStreams(max: 4);
```

| 布局 | `LayoutMode` |
| --- | --- |
| 单主讲 | `speaker` |
| 主画面 + 缩略 | `pip` |
| 等分网格 | `grid` |

## 渲染

```dart
RtcVideoView(
  subscriber: remote,
  mirror: false,
  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
);
```

本地预览则传 `renderer` 而非 `subscriber`。

## 重新订阅

重连后或画面冻结时，[`ResilientSession`](resilience) 会自动重新订阅每一路记住的
流。手动调用：

```dart
await resilient.resubscribe('robot-42');
```
