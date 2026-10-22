---
title: Flutter RTC Link
---

# Flutter RTC Link

一个插件同时做实时音视频（WebRTC）与物联网设备管理：双引擎可互换地推流与订阅、
按流切换清晰度、直播转接、通过低时延控制链路遥控机器人、设备配网 / 升级 / 诊断，
并内置面向海外跨公网链路的韧性层。

版本：**__RTCLINK_VERSION__** · 许可：MPL-2.0 · 平台：Android、iOS

---

## 三通道分离，绝不混用

```
媒体    WebRTC（WHIP/WHEP 或 LiveKit）  视频 / 音频 / 屏幕
控制    MQTT 或 DataChannel            遥控指令、PTZ、遥测、设备信令
业务    HTTPS                          令牌、设备绑定、OTA 分发、报告归档
```

三条通道各自独立降级：网络变差时先降视频，再降音频，控制指令最后才降。

---

## 双引擎，统一抽象

| | WHIP/WHEP 引擎 | LiveKit 引擎 |
| --- | --- | --- |
| 底层包 | `flutter_webrtc` | `livekit_client` |
| 适用 | 自建 SRS / ZLMediaKit / MediaMTX、IoT 摄像头播放 | 互动房间、连麦、大并发围观 |
| 信令 | HTTP（RFC 9725） | LiveKit 服务端 + JWT |
| 重协商 | 禁止——改用 `replaceTrack`，ICE 重启时重建 | 支持 |

两者暴露同一套接口：`RtcEngine` → `RtcSession` → `LocalPublisher` /
`RemoteSubscriber`，共享 `RtcEvent` 事件流与 `RtcStats`。

---

## 能力一览

| 领域 | 入口 |
| --- | --- |
| 推流（摄像头 / 麦克风 / 屏幕、simulcast） | `LocalPublisher` |
| 订阅与清晰度切换 | `RemoteSubscriber`、`VideoGridController` |
| 直播转接与角色交接 | `RoleTransfer`、`StreamRelay` |
| 机器人远控 | `RobotController`、`TeleopChannel` |
| 设备配网、OTA、日志、诊断 | `DeviceProvisioning`、`OtaUpdater`、`DeviceLogCollector`、`Diagnostics` |
| 权限 | `RtcPermissions` |
| **韧性（海外、切网、弱网、后台）** | `ResilientSession`、`RelayPlanner`、`NetworkPathMonitor`、`MediaHealthMonitor`、`PauseResumeGate` |

---

## 从这里开始

- [安装](installation) —— 添加依赖与平台配置
- [快速开始](quick-start) —— 第一条推拉流链路
- [韧性](resilience) —— **出海前必读**
- [机器人远控](robot) —— 摇杆、看门狗与暂停恢复流程
- [设备管理](devices) —— 配网、OTA、日志、诊断
- [常见问题](faq) —— 平台差异与踩坑

英文文档见站点的根路径（右上角可返回 [English](/)。
