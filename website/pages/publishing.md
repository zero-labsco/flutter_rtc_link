# Publishing

`LocalPublisher` is the single publishing surface for both engines.

```dart
final publisher = session.localPublisher!;
```

| Method | Notes |
| --- | --- |
| `startCamera({facing, deviceId, maxClarity})` | Rear/front/external camera selection |
| `startMic()` | Joins audio; mute is separate |
| `startScreenShare({maxClarity})` | Screen or window capture |
| `switchCamera({facing, deviceId})` | `replaceTrack` only — **never renegotiates** |
| `setPublishClarity(level)` | Caps the **top** simulcast layer |
| `setMicEnabled(bool)` / `setCameraEnabled(bool)` | Mute without tearing down |

## Switching sources without renegotiation

WHIP (RFC 9725) forbids changing media sections after the initial SDP, so the
plugin never renegotiates. Track changes use `replaceTrack`:

```dart
await publisher.switchCamera(facing: CameraFacing.front);   // no ICE, no SDP
await publisher.startScreenShare();                          // adds a sender once
await publisher.stopScreenShare();                           // back to the camera
```

:::tip
Keep the sender alive and only swap the track. Creating and closing senders on
every switch is what causes "one second of black video" on WHIP servers.
:::

## Simulcast

Publishing always opens simulcast layers when the server supports them:

| `maxClarity` | Layers published |
| --- | --- |
| `p2160` | 2160p / 1080p / 540p |
| `p1080` | 1080p / 720p / 360p |
| `p720` | 720p / 360p |
| `p360` | 360p |

`setPublishClarity` only raises or lowers the **top** layer; lower layers stay
available, so subscribers on slow links are never punished by the publisher's
choice.

```dart
await publisher.setPublishClarity(ClarityLevel.p720); // cap, do not restart
```

## Bitrate and degradation

Let the server and the bandwidth estimator do the work. Only intervene when
[`MediaHealthMonitor`](resilience) reports sustained congestion:

```dart
session.stats.listen((stats) {
  if (stats.packetLossPercent > 12) {
    unawaited(publisher.setPublishClarity(ClarityLevel.p360));
  }
});
```

## Leaving the session

```dart
await publisher.stop();  // stops tracks, keeps the session alive
await session.leave();   // tears the whole thing down
```
