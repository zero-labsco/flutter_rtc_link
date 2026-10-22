# 常见问题

## 需要自己搭服务器吗？

需要。插件只做客户端。WHIP/WHEP 用 SRS、ZLMediaKit 或 MediaMTX；房间语义用
LiveKit 服务端；自建则实现 `RtcSignaling` / `RtcSession`。

## 一定要部署 TURN 吗？

只要出了自己的局域网，就必须。摄像头与机器人的 NAT 常常是对称型或在 CGNAT 之后，
单靠 STUN 打不通。`RelayPlanner` 会在直连失败 `relayAfterAttempts` 次后升级到
`RelayMode.forced`。

## 为什么我的摄像头切不了清晰度？

因为它只推单层码流，单层流没有软件清晰度切换能力。要么服务端转码，要么把主/子码流
发布成不同 stream id（`_sd` / `_hd` / `_fhd`），插件会在其间切换（有 1~2s 闪断）。

## 为什么 UI 显示"已连接"但画面是冻结的？

ICE 状态不等于媒体状态。这正是 `MediaHealthMonitor` 存在的意义：它从 stats 判定
`frozen`，并逐级升级到请求关键帧、重建订阅。`LinkPhase.degraded` 必须渲染为告警，
不能显示成"已连接"。

## 为什么切网时插件要重建 peer connection？

WHIP/WHEP（RFC 9725）禁止在初始 SDP 之后重协商，因此 ICE 重启只能表达为"用全新
ICE 配置重建连接"。换轨道不走这条路——它用 `replaceTrack`。

## 为什么恢复必须由人确认？

因为不确认会有危险。中断前采集到的指令（比如应用后台期间摇杆被推到左边），在链路
恢复时已经不再有效。`PauseResumeGate` 在每次暂停时递增 epoch，让这些操作失效，并
要求显式确认才能开启新的 epoch。

## 可以关掉暂停 / 恢复流程吗？

可以不传 `gate`（退回旧行为），或在自定义策略中调用
`resumeImmediately(afterReconnect: true)`。两者都是显式退出，且都不是默认行为。

## 为什么 BLE 配网没有用官方 ESP 包？

`esp_provisioning_ble` 锁定 `protobuf ^3`，与 `livekit_client` 的
`protobuf ^4/^6` 冲突。插件直接用 `cryptography` 实现了 protocomm Security1
（`lib/src/device/protocomm.dart`），彻底移除该依赖。

## iOS 能用 NFC 碰一碰配网吗？

只能读，且需要 entitlement
`com.apple.developer.nfc.readersession.formats`（付费账号 + 显式 App ID，不支持
通配符）。iOS 不能模拟标签（HCE）。

## iOS 能自动连设备热点吗？

不能。Apple 禁止程序化加入 Wi-Fi，只能引导用户去设置页操作。

## Android 14 后台录音为什么崩？

缺 `FOREGROUND_SERVICE_MICROPHONE` 与 `foregroundServiceType="microphone"`，
Android 会在启动服务时抛 `SecurityException`。插件已内置
`RtcLinkForegroundService` 并合并声明。

## 模拟器能测吗？

只能测 UI 与逻辑。iOS 模拟器没有摄像头 / NFC / 蓝牙；Android 模拟器无法做 BLE、
NFC 与 SoftAP。设备管理能力必须有真机。

## 英文文档在哪？

站点根路径（可返回 [English](/)。
