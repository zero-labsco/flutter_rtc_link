# 机器人远控

```dart
final robot = RobotController(
  channel: MqttTeleopChannel(broker: 'mqtts://mqtt.example.com:8883'),
  gate: gate,           // epoch 管控，强烈建议接入
  rateLimiter: CommandRateLimiter(minInterval: const Duration(milliseconds: 100)),
);
await robot.connect(deviceId: 'robot-42');
```

## 驾驶

```dart
// 由摇杆偏移换算
final v = velocityFromJoystick(dx: 0.4, dy: -0.8, maxLinear: 1.0, maxAngular: 1.5);
await robot.move(v);

// PTZ 走独立通道，绝不进 WebRTC
await robot.setPtz(pan: 30, tilt: -10);

// 显式停车：撤防看门狗，且一定送达
await robot.stop();
```

指令每 `commandInterval`（默认 100ms）重发一次，丢一个包也不会让机器人盲开。

## 看门狗

| 事件 | 行为 |
| --- | --- |
| 超过 `watchdogTimeout`（500ms）没有新指令 | 立即停车 + 上报 `RobotWatchdogTriggered` |
| 通道拒绝发送 | 立即停车——被拒意味着失去控制，而不是"稍后再试" |
| 通道断开 | 与指令超时同等处理 |

```dart
robot.events.whereType<RobotWatchdogTriggered>().listen((e) {
  showBanner('看门狗触发：${e.sinceLastCommand.inMilliseconds} ms');
});
```

:::warning
看门狗是安全特性，不是便利开关。不要把 `watchdogTimeout` 调到机器人能承受的范围
之外——500ms 这个预算存在的理由，是机器人收完最后一个包还会继续动。
:::

## 暂停 / 恢复（防止事故的关键）

```dart
// 应用进后台或链路中断
await robot.pause(PauseReason.background);
// → 立即发 stop
// → 撤防看门狗
// → epoch++，此前所有指令失效

// 回来必须确认
final ticket = robot.requestResume();
final ok = await robot.confirmResume(ticket);
```

保证如下：

- 挂起期间采集到的摇杆位置被**丢弃**而非补发，机器人不会因过期输入重新动起来；
- 保活循环每拍重新校验 epoch，暂停前的速度无法溜过去；
- 外来或过期票据一律拒绝并上报原因。

```dart
robot.events.whereType<RobotStaleCommandDropped>().listen((e) {
  debugPrint('丢弃 epoch ${e.epoch}，当前 ${e.currentEpoch}');
});
```

## 遥测

```dart
robot.channel.telemetry.listen((t) {
  debugPrint('电量 ${t.battery} · 速度 ${t.speed}');
});
```

## 选择控制通道

```dart
final selection = ControlLinkRouter(rttBudgetMs: 200).select(paths);
```

| 通道 | 适用 |
| --- | --- |
| `ControlLinkKind.dataChannel` | 首选——随 WebRTC 连接走，约 12ms |
| `ControlLinkKind.mqtt` | 跨公网 / 跨区域回退，约 180ms |

路由器还会报告所选路径是否在 `rttBudgetMs` 预算内，让 UI 在操作员开动之前就给出
提示。
