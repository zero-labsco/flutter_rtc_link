# 韧性

办公室局域网能跑通的链路，到了公网——尤其是跨境——会暴露出完全不同的失败模式。
本页即插件 `lib/src/resilience/` 模块存在的全部理由。

## 只有出海才会遇到的失败模式

| 场景 | 局域网表现 | 公网表现 |
| --- | --- | --- |
| 连接建立 | 一次成功 | 首次 SDP 往返可能 5~15s，甚至静默超时 |
| NAT 穿越 | STUN 足够 | CGNAT、酒店 Wi-Fi、对称型 NAT、跨境丢包 |
| 网络切换 | 几乎不发生 | Wi-Fi ↔ 蜂窝反复切换，IP 变了但 socket 看着还活着 |
| 弱网 | 带宽稳定 | 丢包抖动，RTT 从 60ms 涨到 600ms+ |
| 画面冻结 | — | 仍显示"已连接"，但 fps 掉到 0 |
| 后台 | — | Android / iOS 随时回收或降权 |
| 断线重连 | 秒级恢复 | 抖动链路反复上下线，重连风暴与指令重复 |

## 包一层即可

```dart
final monitor = CallbackNetworkMonitor(); // 由 connectivity_plus 喂数据
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

### 链路阶段

`resilient.health` 返回带 `LinkPhase` 的 `LinkHealth`：

`idle` → `connecting` → `connected`（或 `degraded`）→ `reconnecting` → `connected` / `failed`

`degraded` 表示"连着，但媒体在卡顿或拥塞"——UI 绝不能在这一状态下亮绿灯。

## 连接建立

- `LinkPolicy.connectTimeout` 约束首次尝试；失败抛出 `RtcException` 而不是挂起。
- 重试由 `ReconnectSupervisor` 管控，**带抖动**的指数退避（`jitterRatio`），
  避免一整批设备同时重试。
- `stableWindow` 防止抖动：刚起来又断的链路**不会**重置尝试计数，否则永远升不到
  中继。

```dart
final delay = supervisor.scheduleNext(); // 预算耗尽后返回 null
supervisor.recordFailure();              // 或 recordSuccess()
```

## 中继 / TURN

```dart
final relay = RelayPlanner(
  servers: iceServers,
  preferredRegions: <String>['ap', 'eu'],
);

final config = relay.configurationFor(RelayMode.forced);
// {'iceServers': [turn…], 'iceTransportPolicy': 'relay'}

final mode = relayModeForAttempt(3, relayAfterAttempts: 2); // → RelayMode.forced
```

- `auto` —— 就近区域优先，允许直连；
- `forced` —— 只走 TURN，并带 `iceTransportPolicy: relay`；
- `direct` —— STUN 优先，TURN 最后。

:::warning
没有配置 TURN 却强制中继必然失败。此时插件会退化为 `auto`，而不是盲目执行请求。
:::

## 网络切换

```dart
monitor.update(NetworkPath(kind: NetworkKind.cellular, generation: 7, metered: true));
```

`NetworkPath` 带 `generation`，因此能区分"同类型漫游"与"真正换链"：

| 变化 | `requiresIceRestart()` |
| --- | --- |
| Wi-Fi → 蜂窝 | `true` |
| Wi-Fi → 无网络 | `false`（链路被暂停，没有可重启的对象） |
| Wi-Fi → 另一个 Wi-Fi | 默认 `false`；`restartOnSameKind: true` 时为 `true` |

真正的换链会调用 `IceRestartable.restartIce()`。WHIP/WHEP 不支持重协商
（RFC 9725），因此这里用**全新的 ICE 配置重建** peer connection——强制 TURN 时
带 `relay`。

## 弱网与画面冻结

`MediaHealthMonitor` 带去抖地把 `RtcStats` 判定为三类问题：

| 问题 | 触发条件 | 恢复阶梯 |
| --- | --- | --- |
| `stuttering` | 丢包 ≥ 6% 或 jitter ≥ 120ms | 观察，必要时降档 |
| `congested` | RTT ≥ 400ms 或丢包 ≥ 12% | 超过 `degradeAfter` 后降档 |
| `frozen` | fps ≤ 2 但仍有流量 | 请求关键帧 → 重建订阅 |

```dart
final health = media.feed(stats);
if (health.action == MediaRecoveryAction.resubscribe) {
  await resilient.resubscribe(health.streamId);
}
```

判定要快但**带去抖**（`frozenSamples`），恢复要慢且需要连续多个好样本
（`recoverySamples`）——一个偶然的好样本不能解除降级状态。

## 后台与前台

```dart
final lifecycle = AppLifecycleGate(
  onBackgroundChanged: (background) => resilient.setBackground(background),
)..attach();
```

`paused`、`hidden`、`detached` 一律按后台处理。`BackgroundPolicy` 决定宽限期、
是否关闭视频轨道、是否停车。

## 断线重连

1. 退避开始前先拆掉死会话——不留孤立定时器；
2. 重新订阅每一路记住的流，并恢复其最后的清晰度；
3. 控制操作在恢复被确认之前保持失效（见下）。

## 暂停 / 恢复：绝不补发过期操作

```
pause(reason)
   └── epoch++ → 所有在飞与缓存操作立即过期
   └── 机器人立即停车（RobotController.pause 发 stop 并撤防看门狗）

requestResume()  → ResumeTicket(epoch = 下一个, 会过期)
confirmResume(ticket) → 校验：已暂停？票据一致？未过期？
   └── true  → epoch 落定，只有新盖戳的操作才会执行
   └── false → 上报原因（"no ticket issued" / "ticket expired" / "ticket mismatch"）
```

```dart
final gate = PauseResumeGate();
final queue = EpochOperationQueue<Velocity>(gate);

queue.submit(const Velocity(linear: 0.6)); // epoch 1
gate.pause(PauseReason.background);        // epoch 2：此前一切过期

final ticket = gate.requestResume();       // 绑定 epoch 3，会过期
if (gate.confirmResume(ticket)) {
  queue.take();                            // null → 已丢弃，不是补发
}

debugPrint('已丢弃 ${queue.gate.discardedOperations} 条');
```

插件强制执行的三条规则：

1. 暂停期间产生的操作一律**丢弃并计数**，绝不缓存到恢复后补发；
2. `RobotController` 的保活每拍都重新校验 epoch，暂停前的速度无法溜过去；
3. 恢复必须由**人**确认，或由策略显式调用 `resumeImmediately(afterReconnect: true)`。

## 低时延控制链路

```dart
final selection = ControlLinkRouter(rttBudgetMs: 200).select(<ControlLinkPath>[
  const ControlLinkPath(kind: ControlLinkKind.dataChannel, id: 'dc', rttMs: 12),
  const ControlLinkPath(kind: ControlLinkKind.mqtt, id: 'wan', rttMs: 180),
]);
```

- 可达时走数据通道，不可达回退 MQTT；
- `ControlRttTracker`（EMA）识别"名义在线、实际超时"的链路；
- `CommandRateLimiter` 对摇杆做限流（最新者胜），而不是把链路灌满；
- 预算：控制端到端 < 200ms（局域网 < 80ms），视频首帧 < 800ms。

## 出海前自检

- [ ] TURN 已部署，且从公司外网可达；
- [ ] `preferredRegions` 与设备实际所在区域一致；
- [ ] `setBackground` 已接到应用生命周期；
- [ ] 恢复确认接的是真实 UI 动作，而不是定时器；
- [ ] `health.phase == degraded` 渲染为告警，而不是绿灯。
