# BLE Teleop Control

The plugin ships a **persistent BLE GATT control channel** for robot
teleoperation, alongside the existing MQTT and WebRTC DataChannel transports.
It implements the same `TeleopChannel` interface, so it drops straight into
`RobotController` (and `DualTeleopChannel`) — the watchdog, epoch gating and
keepalive are identical; only the transport changes.

> This is **not** the BLE *provisioning* path (`EspBleProvisioningChannel`).
> Provisioning is a one-shot Wi-Fi handoff; the teleop channel is a long-lived
> link that carries commands and telemetry continuously.

## GATT contract

The robot firmware must expose one service with two characteristics (defaults
below; override via the constructors if your firmware already reserves other
UUIDs):

| Role | UUID | Direction | Use |
| --- | --- | --- | --- |
| Service | `7e4e1700-cb3e-4b5f-9b2a-1c6e8d3f4a5b` | — | Teleop service |
| Command | `…1701…` (same base) | phone → device, write | JSON command |
| Telemetry | `…1702…` (same base) | device → phone, notify | JSON telemetry |

## Command envelope

The phone writes one JSON object per command:

| `type` | Fields |
| --- | --- |
| `velocity` | `linear`, `angular` |
| `ptz` | `pan`, `tilt`, `zoom?` |
| `stop` | — |

## Telemetry envelope

The device notifies a JSON object parsed by `RobotTelemetry` (it tolerates
`linearSpeed`/`v`, `angularSpeed`/`w`, `battery`, `pose`, `online`).

## Usage

```dart
final discoverer = BleTeleopDiscoverer();
final devices = await discoverer.scan();          // List<BleDevice>
final channel = BleTeleopChannel.forDevice(devices.first);
final robot = RobotController(channel: channel);
await robot.connect(deviceId: devices.first.id);   // scans/connects GATT, MTU
robot.move(velocityFromJoystick(dx: dx, dy: dy, maxLinear: 1, maxAngular: 1.5));
```

`BleTeleopChannel` requests a larger MTU (256) and subscribes to telemetry
notifications automatically.

## Resilience

`FlutterBluePlusBleLink` **auto-reconnects** on a drop (capped attempts,
exponential backoff), so a brief BLE glitch never silently kills the link. A
drop still trips the `RobotController` **watchdog** if it outlasts
`watchdogTimeout`, so the robot always stops on a *real* loss of control.

## As a network fallback

```dart
final channel = DualTeleopChannel(
  primary: MqttTeleopChannel(broker: …, topicCmd: …, topicTelemetry: …),
  secondary: BleTeleopChannel.forDevice(device),
);
```

Network is primary, BLE is secondary: BLE keeps delivering stop commands even
when the network link dies.
