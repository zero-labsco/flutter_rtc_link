# Resilience

A link that works in the office LAN fails differently on the public internet —
especially across borders. This page is the whole point of the plugin's
`lib/src/resilience/` layer.

## Failure modes you only meet outside the LAN

| Situation | LAN behaviour | Public-internet behaviour |
| --- | --- | --- |
| Connect | Succeeds first try | First SDP round trip can take 5–15 s, or time out silently |
| NAT | STUN is enough | CGNAT, hotel Wi-Fi, symmetric NAT, lossy cross-border paths |
| Handover | Rare | Wi-Fi ↔ cellular repeatedly, IP changes while the socket looks alive |
| Weak network | Stable bandwidth | Loss and jitter; RTT climbs from 60 ms to 600 ms+ |
| Frozen picture | — | Still "connected", fps drops to 0 |
| Background | — | Android/iOS reclaim or downgrade the app at any time |
| Reconnect | Instant | Flapping link, infinite retry storm, duplicated commands |

## Wrap your session

```dart
final monitor = CallbackNetworkMonitor(); // feed it from connectivity_plus
final resilient = await ResilientSession.connect(
  roomId: 'robot-42',
  role: RtcRole.robotOperator,
  factory: engine.join,
  config: ResilientSessionConfig(
    policy: const LinkPolicy(
      connectTimeout: Duration(seconds: 12),
      reconnect: ReconnectPolicy(maxAttempts: 8, relayAfterAttempts: 2),
      restartIceOnHandover: true,
    ),
    relay: RelayPlanner(servers: iceServers, preferredRegions: <String>['ap']),
    monitor: monitor,
  ),
);
```

### Link phases

`resilient.health` exposes a `LinkHealth` with a `LinkPhase`:

`idle` → `connecting` → `connected` （或 `degraded`）→ `reconnecting` → `connected` / `failed`

`degraded` means "connected, but the media is stuttering or congested" — the UI
must not show a green "connected" LED in that state.

## Connection establishment

- `LinkPolicy.connectTimeout` bounds the first attempt; a failed connect
  rethrows an `RtcException` instead of hanging.
- Retries are supervised by `ReconnectSupervisor` with **jittered** exponential
  backoff (`jitterRatio`), so a fleet of devices does not retry in lockstep.
- `stableWindow` protects against flapping: a link that fails again shortly
  after coming up does **not** reset the attempt counter, otherwise it could
  never escalate to relay.

```dart
final delay = supervisor.scheduleNext();   // null once the budget is gone
supervisor.recordFailure();                // or recordSuccess()
```

## Relay / TURN

```dart
final relay = RelayPlanner(
  servers: iceServers,
  preferredRegions: <String>['ap', 'eu'],
);

final config = relay.configurationFor(RelayMode.forced);
// {'iceServers': [turn…], 'iceTransportPolicy': 'relay'}

final mode = relayModeForAttempt(3, relayAfterAttempts: 2); // → RelayMode.forced
```

- `auto` — nearest region first, direct attempts allowed.
- `forced` — TURN only, with `iceTransportPolicy: relay`.
- `direct` — STUN first, TURN last.

:::warning
Forcing relay with no TURN server configured guarantees failure. The plugin
falls back to `auto` in that case instead of obeying the request blindly.
:::

## Network switching

```dart
monitor.update(NetworkPath(kind: NetworkKind.cellular, generation: 7, metered: true));
```

`NetworkPath` carries a `generation` so a same-kind roam (Wi-Fi → another
Wi-Fi) is distinguishable from a real handover:

| Change | `requiresIceRestart()` |
| --- | --- |
| Wi-Fi → cellular | `true` |
| Wi-Fi → none | `false` (the link is paused, there is nothing to restart) |
| Wi-Fi → another Wi-Fi | `false` by default, `true` with `restartOnSameKind: true` |

On a real handover the session calls `IceRestartable.restartIce()`. WHIP/WHEP
cannot renegotiate (RFC 9725), so the peer connection is **rebuilt** with a
fresh ICE configuration — including `relay` when TURN is forced.

## Weak network and frozen pictures

`MediaHealthMonitor` debounces `RtcStats` into three issues:

| Issue | Trigger | Recovery ladder |
| --- | --- | --- |
| `stuttering` | loss ≥ 6 % or jitter ≥ 120 ms | wait, then downgrade |
| `congested` | RTT ≥ 400 ms or loss ≥ 12 % | downgrade clarity after `degradeAfter` |
| `frozen` | fps ≤ 2 with traffic still flowing | keyframe → re-subscribe |

```dart
final health = media.feed(stats);
if (health.action == MediaRecoveryAction.resubscribe) {
  await resilient.resubscribe(health.streamId);
}
```

Detection is fast but **debounced** (`frozenSamples`); recovery is slow and
requires several good samples (`recoverySamples`) — a single lucky sample must
not clear a degraded state.

## Background and foreground

```dart
final lifecycle = AppLifecycleGate(
  onBackgroundChanged: (background) => resilient.setBackground(background),
)..attach();
```

`paused`, `hidden` and `detached` all count as background. `BackgroundPolicy`
decides what happens: a grace period, whether to drop the video track, and
whether to stop the robot.

## Reconnect

1. The dead session is torn down before the backoff starts — no orphaned timers.
2. Every remembered stream is re-subscribed, with its last clarity.
3. Control operations stay invalidated until the resume is confirmed (below).

## Pause / resume: never replay an expired operation

```
pause(reason)
   └── epoch++ → every in-flight and buffered operation is now stale
   └── robot stops immediately (RobotController.pause sends stop, disarms watchdog)

requestResume()  → ResumeTicket(epoch = next, expires)
confirmResume(ticket) → checks: paused? same ticket? not expired?
   └── true  → epoch advances, only freshly stamped operations run
   └── false → reason reported ("no ticket issued" / "ticket expired" / "ticket mismatch")
```

```dart
final gate = PauseResumeGate();
final queue = EpochOperationQueue<Velocity>(gate);

queue.submit(const Velocity(linear: 0.6)); // epoch 1
gate.pause(PauseReason.background);        // epoch 2 — everything older is stale

final ticket = gate.requestResume();       // bound to epoch 3, expires
if (gate.confirmResume(ticket)) {
  queue.take();                            // null → dropped, NOT replayed
}

final gate2 = queue.gate;
debugPrint('dropped ${gate2.discardedOperations}');
```

Rules the plugin enforces:

1. Operations produced while suspended are **dropped and counted**, never
   buffered for a later replay.
2. `RobotController`'s keepalive re-checks the epoch, so a pre-pause velocity
   can never be replayed.
3. Resuming needs a **human** confirmation, or an explicit
   `resumeImmediately(afterReconnect: true)` policy decision.

## Low-latency control link

```dart
final selection = ControlLinkRouter(rttBudgetMs: 200).select(<ControlLinkPath>[
  const ControlLinkPath(kind: ControlLinkKind.dataChannel, id: 'dc', rttMs: 12),
  const ControlLinkPath(kind: ControlLinkKind.mqtt, id: 'wan', rttMs: 180),
]);
```

- Data channel when reachable, MQTT when it is not.
- `ControlRttTracker` (EMA) detects a link that is nominally online but
  practically timed out.
- `CommandRateLimiter` throttles joystick input (latest wins) instead of
  flooding the link.
- Budget: control end-to-end < 200 ms (LAN < 80 ms), first video frame < 800 ms.

## Checklist before shipping

- [ ] TURN deployed and reachable from outside your office network.
- [ ] `preferredRegions` matches where your devices actually are.
- [ ] `setBackground` wired to the app lifecycle.
- [ ] Resume confirmation wired to a real UI action, not to a timer.
- [ ] `health.phase == degraded` renders a warning, not a green LED.
