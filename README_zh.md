# Flutter RTC Link

<div align="center" style="display: flex; align-items: center; justify-content: center; gap: 24px;">

<span style="font-size: 1.1em; padding: 0 8px;"><strong>绠€浣撲腑鏂?/strong> &nbsp;|&nbsp; <a href="README.md">English</a></span>

</div>

涓€涓?Flutter 鎻掍欢鍚屾椂鎼炲畾瀹炴椂闊宠棰戯紙WebRTC锛夊拰鐗╄仈缃戣澶囩鐞嗭細鐢ㄤ袱濂楀彲浠绘剰鍒囨崲鐨勫紩鎿庢帹娴?/ 鎷夋祦锛屾瘡鏉℃祦閮借兘鍗曠嫭璋冩竻鏅板害锛屽苟鏀寔鐩存挱娴佽浆鎺紱杩樿兘閫氳繃浣庡欢杩熸帶鍒堕€氶亾杩滅▼鎿嶆帶鏈哄櫒浜猴紝浠ュ強瀵硅澶囧仛閰嶇綉銆佸浐浠跺崌绾т笌璇婃柇銆傛澶栧唴缃竴灞備笓涓烘捣澶?/ 璺ㄥ叕缃戝急缃戠幆澧冩墦閫犵殑闊ф€ц兘鍔涳紙鑷姩閲嶈繛銆佸急缃戞仮澶嶃€佷腑缁у垏鎹㈢瓑锛夈€?
[![pub version](https://img.shields.io/pub/v/flutter_rtc_link.svg)](https://pub.dev/packages/flutter_rtc_link)
[![pub points](https://img.shields.io/pub/points/flutter_rtc_link.svg)](https://pub.dev/packages/flutter_rtc_link/score)
[![CI](https://github.com/zero-labsco/flutter_rtc_link/actions/workflows/ci.yml/badge.svg)](https://github.com/zero-labsco/flutter_rtc_link/actions/workflows/ci.yml)
[![License: MPL-2.0](https://img.shields.io/badge/License-MPL--2.0-blue.svg)](https://github.com/zero-labsco/flutter_rtc_link/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green.svg)](https://pub.dev/packages/flutter_rtc_link)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%9C%93-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%E2%9C%93-0175C2?logo=dart)](https://dart.dev)
[![Style: effective dart](https://img.shields.io/badge/style-effective_dart-40c4ff.svg)](https://pub.dev/packages/effective_dart)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-4cc38a.svg)](https://zero-labsco.github.io/flutter_rtc_link/)

> **馃敂 鎺ㄨ崘鍗囩骇锛?* `0.3.1` 鏂板 **鍩轰簬 BLE GATT 鐨勬寔涔呮帶鍒堕€氶亾**鈥斺€擿BleTeleopChannel` 瀹炵幇 `TeleopChannel`锛屽彲鐩存帴鎺ュ叆 `RobotController` / `DualTeleopChannel`锛堢湅闂ㄧ嫍銆乪poch 闂ㄦ帶涓庝繚娲婚€昏緫涓嶅彉锛夛紝鏂嚎鑷姩閲嶈繛锛屽苟閰嶅 `BleTeleopDiscoverer` 鎵弿鍣ㄣ€傚彲鐢ㄤ簬鐩磋繛銆佸厤缃戠粶鐨勮繙鎺э紝鎴栦綔涓虹綉缁滄柇閾炬椂鐨勫厹搴曘€傚缓璁墍鏈夌敤鎴峰崌绾у埌鏈€鏂扮増鏈紙`^0.3.1`锛夈€?
馃寪 **[鏂囨。绔橾(https://zero-labsco.github.io/flutter_rtc_link/)** &nbsp;路&nbsp; 馃摝 **[鍦?pub.dev 鏌ョ湅](https://pub.dev/packages/flutter_rtc_link)** &nbsp;路&nbsp; 馃敆 **[鏌ョ湅 GitHub 浠撳簱](https://github.com/zero-labsco/flutter_rtc_link)**

---

## 鐩綍

- [鍔熻兘鐗规€(#鍔熻兘鐗规€?
- [瀹夎](#瀹夎)
- [浣跨敤](#浣跨敤)
  - [蹇€熷紑濮媇(#蹇€熷紑濮?
  - [鎺ㄦ祦](#鎺ㄦ祦)
  - [璁㈤槄](#璁㈤槄)
  - [闊ф€э紙娴峰銆佸垏缃戙€佸急缃戙€佸悗鍙帮級](#闊ф€ф捣澶栧垏缃戝急缃戝悗鍙?
  - [鏈哄櫒浜鸿繙鎺(#鏈哄櫒浜鸿繙鎺?
  - [璁惧绠＄悊](#璁惧绠＄悊)
  - [鏉冮檺](#鏉冮檺)
- [API 鍙傝€僝(#api-鍙傝€?
- [绀轰緥](#绀轰緥)
- [娴嬭瘯](#娴嬭瘯)
- [鏂囨。](#鏂囨。)
- [璐＄尞](#璐＄尞)
- [璁稿彲](#璁稿彲)

---

## 鍔熻兘鐗规€?
- **鍙屽紩鎿庛€佺粺涓€鎶借薄** 鈥斺€?鍩轰簬 `flutter_webrtc` 鐨?WHIP/WHEP 瀵规帴鑷缓 SRS /
  ZLMediaKit / MediaMTX锛屽熀浜?`livekit_client` 鐨?LiveKit 瀵规帴浜掑姩鎴块棿銆傛崲淇′护瀵硅薄
  鍗冲彲锛屽叾浣欎唬鐮侀浂鏀瑰姩銆?- **鎺ㄦ祦涓?simulcast** 鈥斺€?`startCamera` / `startMic` / `startScreenShare`锛?  `switchCamera` 璧?`replaceTrack`锛堥浂閲嶅崗鍟嗭紝绗﹀悎 RFC 9725锛夛紱`setPublishClarity`
  鍙檺鍒舵渶楂樺眰銆?- **璁㈤槄涓庢竻鏅板害鍒囨崲** 鈥斺€?WHEP 鎷夋祦銆佹寜娴?`setClarity`銆佺函 Dart 鐨?  `VideoGridController`锛堜富璁?/ 鐢讳腑鐢?/ 缃戞牸甯冨眬銆佹渶澶у彲瑙佹暟銆佸叏灞€娓呮櫚搴︼級锛?  娌℃湁鍙樹綋娴佹椂鏄庣‘涓婃姤鑰岄潪鍋囪鑳藉垏銆?- **鐩存挱杞帴** 鈥斺€?`RoleTransfer.promote` / `handover`锛堣韩浠戒氦鎺ワ級涓?  `StreamRelay.toRtmp` / `cascade`锛堟湇鍔＄ Egress 鎴栦簩娆?WHIP 鎺ㄦ祦锛夈€?- **鏈哄櫒浜鸿繙鎺?* 鈥斺€?鎽囨潌閫熷害銆佺嫭绔嬮€氶亾鐨?PTZ銆侀仴娴嬨€佸璁叉帴鍏ワ紝浠ュ強鎸囦护瓒呮椂 / 鍙戦€?  琚嫆 / 鏂摼鏃?500ms 鍐呰嚜鍔ㄥ仠杞︾殑鐪嬮棬鐙楋紱鍙︽彁渚涘熀浜?BLE GATT 鐨勬寔涔呮帶鍒堕€氶亾
  锛坄BleTeleopChannel`锛夛紝鍙洿杩炪€佸厤缃戠粶杩滄帶銆?- **闈㈠悜浠绘剰璁惧鐨勯€氱敤 BLE** 鈥斺€?`BleScanner` 鍙彂鐜伴檮杩戜换鎰?BLE 璁惧锛?  `BleGattClient` 璐熻矗杩炴帴銆佸彂鐜?GATT 鏈嶅姟骞舵毚闇插師濮嬬殑 `read` / `write` /
  `subscribe`鈥斺€斾笉鍋氫换浣曟満鍣ㄤ汉鎴?ESP 濂戠害鍋囪锛屽洜姝ら煶鍝?/ 浼犳劅鍣?/ 澶栬绫婚」鐩?  鍚屾牱鑳界敤涓婃彃浠剁殑 BLE 鑳藉姏銆傚熀浜?`flutter_blue_plus`锛屼緷璧栨爲涓伆濂藉彧鏈変竴涓?  钃濈墮搴撱€?- **鐗╄仈缃戣澶囧洓浠跺** 鈥斺€?澶氶€氶亾 `DeviceProvisioning`锛圔LE 鈫?DPP/QR 鈫?NFC 鈫?  SoftAP 鈫?SmartConfig 鑷姩闄嶇骇锛夈€乣OtaUpdater`銆乣DeviceLogCollector`锛堟湰鍦扮紦瀛?+
  鎵归噺琛ヤ紶锛変笌 `Diagnostics`锛坰tats + 缃戠粶鎺㈡祴 + 鏃ュ織 鈫?JSON/Markdown锛夈€?- **闈㈠悜娴峰閾捐矾鐨勯煣鎬?* 鈥斺€?鍙楁帶寤洪摼銆佸甫鎶栧姩閫€閬跨殑閲嶈繛涓庤嚜鍔ㄩ噸璁㈤槄銆乀URN 涓户鍗囩骇銆?  Wi-Fi 鈫?铚傜獫 ICE 閲嶅惎銆佸崱椤?/ 鎷ュ / 鐢婚潰鍐荤粨鑷剤銆?- **鏆傚仠 / 鎭㈠纭** 鈥斺€?姣忎釜鎿嶄綔閮藉甫 epoch 鎴筹紱鏆傚仠鍗冲け鏁堬紝鎭㈠鏄袱姝ョエ鎹彙鎵嬶紝
  涓柇鍓嶉噰闆嗗埌鐨勬寚浠ょ粷涓嶄細鍦ㄦ仮澶嶅悗琚ˉ鍙戙€?- **浣庢椂寤舵帶鍒堕摼璺?* 鈥斺€?`ControlLinkRouter`锛堟暟鎹€氶亾浼樺厛銆丮QTT 鍥為€€銆佸甫鏃跺欢棰勭畻锛夈€?  `ControlRttTracker`銆乣CommandRateLimiter`锛氬厛闄嶈棰戯紝鎺у埗鎸囦护鏈€鍚庢墠鍙楀奖鍝嶃€?- **缁熶竴鏉冮檺鍏ュ彛** 鈥斺€?`RtcPermissions.requestAll(...)` 瑕嗙洊 Android 13/14+ 涓?iOS
  鐨勫悇绫诲潙锛涜鎷掓椂鍔熻兘闄嶇骇骞朵笂鎶?`RtcEvent.permissionDenied`锛屼笉宕╂簝銆?- **璇ユ湁鍘熺敓灏辨湁鍘熺敓** 鈥斺€?Android DPP锛圵i-Fi Easy Connect锛夊钩鍙伴€氶亾 + 楹﹀厠椋庡墠鍙?  鏈嶅姟锛沬OS Swift method channel 妗┿€?- **璺ㄥ钩鍙?* 鈥斺€?Android 涓?iOS銆?
---

## 瀹夎

### 浠?pub.dev 瀹夎锛堟帹鑽愶級

```yaml
dependencies:
  flutter_rtc_link: ^0.3.1
```

### 浠?GitHub 瀹夎

```yaml
dependencies:
  flutter_rtc_link:
    git:
      url: https://github.com/zero-labsco/flutter_rtc_link.git
      ref: release/v0.3.1   # 鎶?0.3.1 鎹㈡垚浣犻渶瑕佺殑鐗堟湰
```

### 骞冲彴閰嶇疆

| 骞冲彴 | 瑕佹眰 |
| --- | --- |
| Flutter | >= 3.35.0 |
| Dart SDK | >= 3.9.0 < 4.0.0 |
| Android | `minSdk 24`锛宍compileSdk 36+` |
| iOS | 15.0+ |

Android 鏉冮檺鐢辨彃浠惰嚜鍔ㄥ悎骞躲€俰OS 鐨勭敤閫斿瓧绗︿覆鏃犳硶鐢辨彃浠舵敞鍏ワ紝璇锋寜闇€鍦?`ios/Runner/Info.plist` 娣诲姞 `NSCameraUsageDescription`銆?`NSMicrophoneUsageDescription`銆乣NSBluetoothAlwaysUsageDescription`銆?`NSLocalNetworkUsageDescription`銆乣NFCReaderUsageDescription` 涓?`UIBackgroundModes: audio`銆?
### 瀵煎叆

```dart
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
```

---

## 浣跨敤

### 蹇€熷紑濮?
```dart
final engine = await RtcEngine.create(
  signaling: WhipWhepSignaling(
    whipUrl: 'https://srs.example.com/rtc/v1/whip/',
    whepUrl: 'https://srs.example.com/rtc/v1/whep/',
    // 璺ㄥ叕缃戝繀椤婚儴缃?TURN銆?    iceServers: <IceServer>[
      const IceServer(urls: 'stun:stun.example.com:3478'),
      IceServer(
        urls: 'turn:turn-ap.example.com:3478',
        username: await token.turnUser(),
        credential: await token.turnPass(),
      ),
    ],
  ),
);

final session = await engine.join(roomId: 'robot-42', role: RtcRole.robotOperator);
final remote = await session.subscribe(streamId: 'robot-42', quality: ClarityLevel.p720);
```

### 鎺ㄦ祦

```dart
final publisher = session.localPublisher!;
await publisher.startCamera(facing: CameraFacing.rear, maxClarity: ClarityLevel.p720);
await publisher.startMic();
await publisher.switchCamera(facing: CameraFacing.front); // replaceTrack锛屼笉閲嶅崗鍟?await publisher.setPublishClarity(ClarityLevel.p360);     // 鍙檺鍒舵渶楂樺眰
```

### 璁㈤槄

```dart
await remote.setClarity(ClarityLevel.p540);   // 鍙奖鍝嶈繖涓€璺?final grid = VideoGridController()..addStream(stream);
grid.setMain('robot-42');
RtcVideoView(subscriber: remote);
```

:::note
鍗曞眰鐮佹祦娌℃湁杞欢娓呮櫚搴﹀垏鎹㈣兘鍔涖€傝涔堟湇鍔＄杞爜锛岃涔堟妸涓?瀛愮爜娴佸彂甯冧负涓嶅悓 stream
id锛坄_sd` / `_hd` / `_fhd`锛夆€斺€旀彃浠朵細鍦ㄥ叾闂村垏鎹紙1~2s 闂柇锛夛紝鍚﹀垯涓婃姤
`claritySwitchUnsupported`銆?:::

### 闊ф€э紙娴峰銆佸垏缃戙€佸急缃戙€佸悗鍙帮級

```dart
final monitor = CallbackNetworkMonitor(); // 鐢?connectivity_plus 鍠傛暟鎹?final resilient = await ResilientSession.connect(
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

await resilient.setBackground(true);   // 鏆傚仠鎿嶄綔骞跺叧闂棰戣建閬?await resilient.setBackground(false);  // 绛惧彂鎭㈠绁ㄦ嵁
await resilient.confirmResume();       // 鎿嶄綔鑰呯‘璁?鈫?鏂?epoch
```

| 鍏虫敞鐐?| 瀹炵幇 |
| --- | --- |
| 杩炴帴寤虹珛 | `LinkPolicy.connectTimeout` + 鍙楁帶閲嶈瘯 |
| 涓户 / TURN | `RelayPlanner` 鎸夊尯鍩熸帓搴忥紝`relayModeForAttempt` 鈫?`iceTransportPolicy: relay` |
| 缃戠粶鍒囨崲 | `NetworkPathMonitor`锛堢被鍨?+ 浠ｆ锛夆啋 `IceRestartable.restartIce` |
| 寮辩綉 | `MediaHealthMonitor`锛氬崱椤?/ 鎷ュ / 鍐荤粨 鈫?鍏抽敭甯?鈫?闄嶆。 鈫?閲嶅缓璁㈤槄 |
| 鍚庡彴 | `AppLifecycleGate` 鈫?`setBackground` 搴旂敤 `BackgroundPolicy` |
| 鏂嚎閲嶈繛 | 甯︽姈鍔ㄩ€€閬匡紝鎭㈠鍚庨噸鏂拌闃呮瘡涓€璺浣忕殑娴?|
| 杩囨湡鎿嶄綔 | `PauseResumeGate` 鐨?epoch 鎴?+ 涓ゆ鎭㈠绁ㄦ嵁 |

```dart
final gate = PauseResumeGate();
final queue = EpochOperationQueue<Velocity>(gate);

queue.submit(const Velocity(linear: 0.6)); // epoch 1
gate.pause(PauseReason.background);        // epoch 2锛氭鍓嶄竴鍒囪繃鏈?
final ticket = gate.requestResume();       // 缁戝畾 epoch 3锛屼細杩囨湡
if (gate.confirmResume(ticket)) {
  queue.take();                            // null 鈫?宸蹭涪寮冿紝涓嶆槸琛ュ彂
}
```

### 鏈哄櫒浜鸿繙鎺?
```dart
final robot = RobotController(channel: mqttChannel, gate: gate);
await robot.connect(deviceId: 'robot-42');
await robot.move(velocityFromJoystick(dx: 0.4, dy: -0.8));
await robot.setPtz(pan: 30, tilt: -10);

await robot.pause(PauseReason.background);        // 鍋滆溅 + 璁╂棫鎸囦护澶辨晥
final ticket = robot.requestResume();             // 闇€鎿嶄綔鑰呯‘璁?await robot.confirmResume(ticket);
```

杩欓噷鍙互浣跨敤浠绘剰 `TeleopChannel`鈥斺€擿MqttTeleopChannel`锛堜簯绔?broker锛夈€?`DataChannelTeleopChannel`锛圵ebRTC锛屽欢杩熸渶浣庯級锛屾垨鐢ㄦ柊澧炵殑
`BleTeleopChannel.forDevice(device)` 寤虹珛鎸佷箙鐨?BLE GATT 閾捐矾銆傛妸涓や釜閫氶亾鍖呰繘
`DualTeleopChannel(primary, secondary)`锛屽嵆浣跨綉缁滄柇浜嗘帶鍒朵粛鑳藉瓨娲伙紙渚嬪缃戠粶涓轰富銆?BLE 涓哄锛夈€?
### 璁惧绠＄悊

```dart
await DeviceProvisioning().provision(
  device,
  wifi: WifiCredential(ssid: ssid, password: password),
);

OtaUpdater(channel: bleChannel).upgrade(
  deviceId: device.id,
  firmwareUrl: signedUrl,
  expectedSha256: sha256,
).listen((p) => debugPrint('${p.percent} %'));

await DeviceLogCollector().flush();
final report = await Diagnostics.run(session: session);
```

### 鏉冮檺

```dart
final results = await RtcPermissions.requestAll(<RtcPermission>{
  RtcPermission.camera,
  RtcPermission.microphone,
  RtcPermission.nearbyWifiDevices,
});
```

---

## API 鍙傝€?
| 鍏ュ彛 | 鐢ㄩ€?|
| --- | --- |
| `RtcEngine.create(signaling:)` | 鎸変俊浠ゅ璞″垱寤哄搴斿紩鎿?|
| `RtcSession` | `join` / `subscribe` / `unsubscribe` / `leave` / `events` / `stats` |
| `LocalPublisher` | `startCamera` / `startMic` / `startScreenShare` / `switchCamera` / `setPublishClarity` |
| `RemoteSubscriber` | `setClarity` / `clarity` 閫氱煡鍣?/ `videoRenderer` |
| `VideoGridController` | 绾?Dart 鐨勫竷灞€涓庢竻鏅板害缂栨帓 |
| `RoleTransfer` / `StreamRelay` | 韬唤浜ゆ帴涓庡獟浣撹浆鍙?|
| `RobotController` | `move` / `setPtz` / `stop` / `pause` / `requestResume` / `confirmResume` |
| `BleTeleopChannel` / `BleTeleopDiscoverer` | 鍩轰簬 BLE GATT 鐨勬寔涔呮帶鍒堕€氶亾涓庤澶囨壂鎻?|
| `ResilientSession` | `connect` / `setBackground` / `confirmResume` / `resubscribe` / `restartIce` |
| `PauseResumeGate` / `EpochOperationQueue<T>` | epoch 绠℃帶涓?鏈€鏂拌€呰儨"缂撳啿 |
| `RelayPlanner` / `NetworkPathMonitor` / `MediaHealthMonitor` | 涓户銆佸垏鎹笌寮辩綉妫€娴?|
| `ControlLinkRouter` / `ControlRttTracker` / `CommandRateLimiter` | 浣庢椂寤舵帶鍒惰矾寰?|
| `DeviceProvisioning` / `OtaUpdater` / `DeviceLogCollector` / `Diagnostics` | 鐗╄仈缃戣澶囧洓浠跺 |
| `RtcPermissions` | 涓€娆℃€ц兘鍔涚敵璇?|

---

## 绀轰緥

```bash
cd example && flutter run
```

鍏釜鏍囩椤碉細`link`锛堟帹娴?/ 璁㈤槄锛夈€乣robot`锛堟憞鏉?+ 鐪嬮棬鐙楋級銆乣device`锛堥厤缃?/
鍗囩骇 / 鏃ュ織锛夈€乣ble`锛圔LE GATT 杩滄帶锛氭壂鎻?/ 杩炴帴 / 鎽囨潌锛夈€乣diag`锛堣瘖鏂姤鍛婏級涓?`resil`锛堥煣鎬у疄楠屽锛氭殏鍋滄仮澶嶇‘璁ゃ€佸垏鎹€佸急缃戙€侀€€閬匡級銆?
---

## 娴嬭瘯

```bash
flutter analyze lib test example/lib
flutter test
```

---

## 鏂囨。

鏂囨。绔欎綅浜?[`website/`](website)锛圢extra 3 + Next.js 14锛夊苟鍙戝竷鍒?GitHub Pages锛?瀹夎銆佸揩閫熷紑濮嬨€佹帹娴併€佽闃呫€侀煣鎬с€佽摑鐗欓仴娴嬫帶鍒躲€佹満鍣ㄤ汉杩滄帶銆佽澶囩鐞嗕笌甯歌闂锛屾瘡绡囬兘鏈?`/zh/`
涓嬬殑涓枃鐗堛€?
```bash
cd website && npm ci && npm run dev
```

---

## 璐＄尞

娆㈣繋璐＄尞锛佹彁浜?issue 鎴?PR 鍓嶈鍏堥槄璇籟璐＄尞鎸囧崡](CONTRIBUTING.md)銆?
- 馃悰 [鎶ュ憡缂洪櫡](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=bug_report.md)
- 馃挕 [鍔熻兘寤鸿](https://github.com/zero-labsco/flutter_rtc_link/issues/new?template=feature_request.md)
- 馃挰 [鍙備笌璁ㄨ](https://github.com/zero-labsco/flutter_rtc_link/discussions)
- 馃摉 [璐＄尞鎸囧崡](CONTRIBUTING.md)

---

## 璁稿彲

Copyright (c) 2026 Zero Labs Co. (AmisKwok)銆傛湰椤圭洰閲囩敤 **Mozilla Public
License 2.0锛圡PL-2.0锛?* 璁稿彲鈥斺€旇瑙?[LICENSE](LICENSE) 鏂囦欢銆傜増鏉冨０鏄庝笌闄勫姞鏉℃
锛堟棤鎷呬繚銆佷笉鑳屼功锛夎 [NOTICE](NOTICE)銆?
- **鍏佽鍟嗕笟浣跨敤銆?* 鍏佽浣跨敤銆佷慨鏀逛笌闂簮鍒嗗彂銆?- **淇敼浜嗘彃浠讹紵** 浣犱慨鏀硅繃鐨勬枃浠跺繀椤讳互婧愮爜褰㈠紡鎸?MPL-2.0 鍙戝竷锛屼絾浣犺嚜宸辩殑搴旂敤
  **鏃犻渶**寮€婧愩€?- **鍘熸牱浣跨敤锛?* 鏃犻渶鍏紑婧愮爜銆?- **涓嶈儗涔︺€?* 鏈粡浜嬪厛涔﹂潰璁稿彲锛屼笉寰椾互 "Zero Labs Co."銆?flutter_rtc_link"銆?  椤圭洰 logo / 鍚夌ゥ鐗╁舰璞″強浣滆€呭鍚嶏紙AmisKwok锛変负琛嶇敓鍝佽儗涔︺€佹帹骞挎垨鏆楃ず璧炲姪涓?  浠庡睘鍏崇郴銆?- **鏃犳媴淇濄€佹棤璐ｄ换銆?* 鐗堟潈鎸佹湁浜哄浠讳綍淇敼鐗堟垨琛嶇敓鐗堟湰涓嶆彁渚涙媴淇濄€佷笉鎵挎媴浠讳綍璐ｄ换锛?  淇敼鐗堟湰蹇呴』鏄庣‘鏍囨敞涓哄凡淇敼銆?
鏈彃浠舵寜"鍘熸牱"鎻愪緵锛屼笉闄勫甫浠讳綍褰㈠紡鐨勬媴淇濄€傚浜庝慨鏀圭増鏈垨琛嶇敓椤圭洰鐨勫姛鑳姐€佸畨鍏ㄦ€?鍙婁娇鐢ㄥ悗鏋滐紝浣滆€呬笉鎵挎媴浠讳綍璐ｄ换銆?