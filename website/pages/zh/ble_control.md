# BLE 遥测控制

插件在既有的 MQTT 与 WebRTC DataChannel 之外，额外提供了一条**基于 BLE GATT 的
持久控制通道**，用于机器人遥操作。它实现的是同一个 `TeleopChannel` 接口，因此可
直接接入 `RobotController`（与 `DualTeleopChannel`）——看门狗、epoch 门控与保活
行为完全一致，只是传输变了。

> 这**不是** BLE *配网* 通道（`EspBleProvisioningChannel`）。配网是一次性 Wi-Fi
> 交接；本通道是一条长期存活的链路，持续搬运指令与遥测。

## GATT 契约

机器人固件须暴露一个包含两个特征的服务（以下为默认值；若固件已占用其它 UUID，
可通过构造参数覆盖）：

| 角色 | UUID | 方向 | 用途 |
| --- | --- | --- | --- |
| 服务 | `7e4e1700-cb3e-4b5f-9b2a-1c6e8d3f4a5b` | — | 遥测服务 |
| 指令 | `…1701…`（同基准） | 手机 → 设备，可写 | JSON 指令 |
| 遥测 | `…1702…`（同基准） | 设备 → 手机，notify | JSON 遥测 |

## 指令封包

手机每次写入一个 JSON 对象：

| `type` | 字段 |
| --- | --- |
| `velocity` | `linear`、`angular` |
| `ptz` | `pan`、`tilt`、`zoom?` |
| `stop` | — |

## 遥测封包

设备 notify 一个 JSON 对象，由 `RobotTelemetry` 解析（兼容
`linearSpeed`/`v`、`angularSpeed`/`w`、`battery`、`pose`、`online`）。

## 用法

```dart
final discoverer = BleTeleopDiscoverer();
final devices = await discoverer.scan();          // List<BleDevice>
final channel = BleTeleopChannel.forDevice(devices.first);
final robot = RobotController(channel: channel);
await robot.connect(deviceId: devices.first.id);   // 扫描 / 连接 GATT、协商 MTU
robot.move(velocityFromJoystick(dx: dx, dy: dy, maxLinear: 1, maxAngular: 1.5));
```

`BleTeleopChannel` 会自动请求更大的 MTU（256）并订阅遥测通知。

## 韧性

`FlutterBluePlusBleLink` 在断线后**自动重连**（有上限、指数退避），短暂的 BLE
抖动不会悄悄掐断链路。但若断线超过 `watchdogTimeout`，仍会触发 `RobotController`
的**看门狗**，确保机器人在*真正*失控时一定停车。

## 作为网络兜底

```dart
final channel = DualTeleopChannel(
  primary: MqttTeleopChannel(broker: …, topicCmd: …, topicTelemetry: …),
  secondary: BleTeleopChannel.forDevice(device),
);
```

网络为主、BLE 为辅：即使网络链路断了，BLE 仍能持续送达停车指令。

## 面向任意设备的通用 BLE

上面的遥测通道是**机器人专属**的（它专门查找遥测 GATT 服务）。对于**音响、
传感器或任何其它外设**，请使用与协议无关的通用 BLE 原语——它们不做任何服务
或协议假设，且公开 API 不暴露 `flutter_blue_plus` 类型：

```dart
// 发现附近设备（不传 serviceUuids 即列出全部）。
final devices = await BleScanner().scan();

// 连接其中一个并查看其 GATT 布局。
final client = BleGattClient(devices.first);
await client.connect();
final services = await client.discoverServices();   // List<BleGattService>
for (final s in services) {
  for (final c in s.characteristics) {
    if (c.canRead) final value = await client.read(c.uuid);
    if (c.canWrite) await client.write(c.uuid, [0x01]);
    if (c.canNotify) client.subscribe(c.uuid).listen(print);
  }
}
await client.disconnect();
```

`BleGattClient` 暴露 `read` / `write`（带或不带响应）/ `subscribe` 与
`connectionState` 流，并在开启 `autoReconnect` 时于断线后自动重连。`BleScanner`
与 `BleGattClient` 均从包根导出，基于 `flutter_blue_plus`，因此依赖树中恰好
只有一个蓝牙库。
