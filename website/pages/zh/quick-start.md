# 快速开始

## 1. 创建引擎

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
```

改用 LiveKit 只需换成 `LiveKitSignaling(url:, token:)`，本页其余代码完全不变。

## 2. 加入会话并订阅

```dart
final session = await engine.join(
  roomId: 'robot-42',
  role: RtcRole.robotOperator,
);

final remote = await session.subscribe(
  streamId: 'robot-42',
  quality: ClarityLevel.p720,
);

// 渲染
RtcVideoView(subscriber: remote);
```

## 3. 推流

```dart
final publisher = session.localPublisher!;
await publisher.startCamera(
  facing: CameraFacing.rear,
  maxClarity: ClarityLevel.p720,
);
await publisher.startMic();

// 只限制 simulcast 最高层，不影响会话。
await publisher.setPublishClarity(ClarityLevel.p360);
```

## 4. 监听事件

```dart
session.events.listen((event) {
  switch (event) {
    case RtcConnectionStateChanged():
      debugPrint('状态 ${event.state}');
    case RtcError():
      debugPrint('错误 ${event.error.code}');
    case RtcDisconnected():
      debugPrint('断开：${event.reason}');
    default:
      break;
  }
});
```

## 5. 让它扛得住真实网络

再加一步即可把会话升级为受控、自愈的链路：

```dart
final resilient = await ResilientSession.connect(
  roomId: 'robot-42',
  role: RtcRole.robotOperator,
  factory: engine.join,
  config: ResilientSessionConfig(
    relay: RelayPlanner(servers: iceServers),
    monitor: CallbackNetworkMonitor(),
  ),
);
```

详见 [韧性](resilience)。

## 离开会话

```dart
await resilient.dispose(); // 或 await session.leave();
await engine.dispose();
```
