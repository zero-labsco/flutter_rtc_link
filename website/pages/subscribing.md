# Subscribing

```dart
final remote = await session.subscribe(
  streamId: 'robot-42',
  quality: ClarityLevel.p720,
);
```

A `RemoteSubscriber` is per-stream: each one owns its own `clarity`
`ValueNotifier`, its renderer and its stats stream.

## Switching clarity

```dart
await remote.setClarity(ClarityLevel.p540);   // this stream only
await session.unsubscribe('robot-42');
```

| Engine | Single-layer stream | Multi-layer / variants |
| --- | --- | --- |
| LiveKit | `videoQuality` maps directly | Layer selection is native |
| WHIP/WHEP | **No software switch** — the plugin switches to the variant stream id (`_sd` / `_hd` / `_fhd`, 1–2 s blink) or reports `claritySwitchUnsupported` | SDP `rid` layer selection |

:::warning
A single-layer stream has no software clarity switch. Either transcode
server-side (ZLMediaKit) or expose main/sub streams as separate stream ids —
the plugin never pretends otherwise.
:::

## Auto quality

`auto` follows `RtcStats`: available bandwidth, packet loss and RTT drive the
layer up or down, and `remote.clarity.value` always reflects the *actual*
current level, so the UI never lies.

## Layouts

`VideoGridController` is pure Dart — no widget, no engine import:

```dart
final grid = VideoGridController();
grid.addStream(stream);
grid.setMain('robot-42');        // main / pip / grid
grid.setGlobalClarity(ClarityLevel.p360);
final visible = grid.visibleStreams(max: 4);
```

| Layout | `LayoutMode` |
| --- | --- |
| Single speaker | `speaker` |
| Main + thumbnails | `pip` |
| Equal grid | `grid` |

## Rendering

```dart
RtcVideoView(
  subscriber: remote,
  mirror: false,
  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
);
```

For a local preview pass a `renderer` instead of a `subscriber`.

## Re-subscribing

After a reconnect or a frozen picture, [`ResilientSession`](resilience)
re-subscribes every remembered stream automatically. Manually:

```dart
await resilient.resubscribe('robot-42');
```
