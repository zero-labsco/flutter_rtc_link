# Robot Teleoperation

```dart
final robot = RobotController(
  channel: MqttTeleopChannel(broker: 'mqtts://mqtt.example.com:8883'),
  gate: gate,           // epoch discipline, strongly recommended
  rateLimiter: CommandRateLimiter(minInterval: const Duration(milliseconds: 100)),
);
await robot.connect(deviceId: 'robot-42');
```

## Driving

```dart
// From a joystick offset.
final v = velocityFromJoystick(dx: 0.4, dy: -0.8, maxLinear: 1.0, maxAngular: 1.5);
await robot.move(v);

// PTZ on its own channel (never inside WebRTC).
await robot.setPtz(pan: 30, tilt: -10);

// Explicit stop: disarms the watchdog and always reaches the robot.
await robot.stop();
```

Commands are repeated every `commandInterval` (default 100 ms) so a lost packet
never leaves the robot driving blind.

## Watchdog

| Event | Behaviour |
| --- | --- |
| No command within `watchdogTimeout` (500 ms) | Immediate stop + `RobotWatchdogTriggered` |
| A send is refused by the channel | Immediate stop — a refused command means control is lost, not "try later" |
| Channel disconnects | Treated exactly like a command timeout |

```dart
robot.events.whereType<RobotWatchdogTriggered>().listen((e) {
  showBanner('watchdog tripped after ${e.sinceLastCommand.inMilliseconds} ms');
});
```

:::warning
The watchdog is a safety feature, not a convenience. Never raise
`watchdogTimeout` above what your robot can tolerate — a 500 ms budget exists
because a robot keeps moving after the last packet it received.
:::

## Pause / resume (the part that prevents accidents)

```dart
// App goes to the background, or the link drops.
await robot.pause(PauseReason.background);
// → sends stop immediately
// → disarms the watchdog
// → bumps the epoch, invalidating every command issued before now

// Coming back requires a confirmation.
final ticket = robot.requestResume();
final ok = await robot.confirmResume(ticket);
```

What is guaranteed:

- The joystick position captured while the app was suspended is **dropped**, not
  replayed. The robot cannot start moving again from a stale input.
- The keepalive loop re-checks the epoch every tick, so a pre-pause velocity
  cannot slip through.
- A foreign or expired ticket is rejected and reported.

```dart
robot.events.whereType<RobotStaleCommandDropped>().listen((e) {
  debugPrint('dropped epoch ${e.epoch}, now ${e.currentEpoch}');
});
```

## Telemetry

```dart
robot.channel.telemetry.listen((t) {
  debugPrint('battery ${t.battery} · speed ${t.speed}');
});
```

## Choosing the control path

```dart
final selection = ControlLinkRouter(rttBudgetMs: 200).select(paths);
```

| Path | When |
| --- | --- |
| `ControlLinkKind.dataChannel` | Preferred — rides the WebRTC connection, ~12 ms |
| `ControlLinkKind.mqtt` | Fallback for cross-public-network / cross-region, ~180 ms |

The router also reports whether the chosen path is inside `rttBudgetMs`, so the
UI can warn the operator before they start driving.
