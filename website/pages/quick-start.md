# Quick Start

## 1. Create an engine

```dart
final engine = await RtcEngine.create(
  signaling: WhipWhepSignaling(
    whipUrl: 'https://srs.example.com/rtc/v1/whip/',
    whepUrl: 'https://srs.example.com/rtc/v1/whep/',
    // TURN is mandatory across the public internet.
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

Swap in `LiveKitSignaling(url:, token:)` to use LiveKit — the rest of this page
is identical.

## 2. Join and subscribe

```dart
final session = await engine.join(
  roomId: 'robot-42',
  role: RtcRole.robotOperator,
);

final remote = await session.subscribe(
  streamId: 'robot-42',
  quality: ClarityLevel.p720,
);

// Render it.
RtcVideoView(subscriber: remote);
```

## 3. Publish

```dart
final publisher = session.localPublisher!;
await publisher.startCamera(
  facing: CameraFacing.rear,
  maxClarity: ClarityLevel.p720,
);
await publisher.startMic();

// Cap the top simulcast layer without touching the session.
await publisher.setPublishClarity(ClarityLevel.p360);
```

## 4. Listen to events

```dart
session.events.listen((event) {
  switch (event) {
    case RtcConnectionStateChanged():
      debugPrint('state ${event.state}');
    case RtcError():
      debugPrint('error ${event.error.code}');
    case RtcDisconnected():
      debugPrint('bye: ${event.reason}');
    default:
      break;
  }
});
```

## 5. Make it survive the real world

One more line turns the session into a supervised, self-healing link:

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

See [Resilience](resilience) for the full picture.

## Leaving

```dart
await resilient.dispose(); // or await session.leave();
await engine.dispose();
```
