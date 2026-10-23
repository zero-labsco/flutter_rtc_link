# flutter_rtc_link_example

Demo app for the [`flutter_rtc_link`](https://pub.dev/packages/flutter_rtc_link) plugin: real-time audio/video (WebRTC WHIP/WHEP + LiveKit) and IoT device management — publish, subscribe, live relay, robot teleoperation, provisioning and OTA.

## Run / 运行

```bash
cd example
flutter pub get
flutter run
```

Requires a Flutter 3.35+ environment. The example targets Android `compileSdk 36` with AGP 9.1.0 by default.

## Local RTC test with MediaMTX / 用本地 MediaMTX 测 RTC

The example's RTC tab defaults to a **local MediaMTX** instance (`http://127.0.0.1:8889/rtc-link/whip` + `/whep`). No public server or account is required — everything runs on your own machine, which also works in networks that cannot reach public WHIP/WHEP endpoints (e.g. behind a firewall / regional blocks).

/ 示例的 RTC 页默认指向**本地 MediaMTX**（`http://127.0.0.1:8889/rtc-link/whip` + `/whep`）。无需公共服务器或账号，全部跑在你自己的电脑上；在无法访问公共 WHIP/WHEP 端点的网络（如防火墙 / 区域限制）下也能用。

1. Download MediaMTX (single Go binary, no config) for your OS from the [releases page](https://github.com/bluenviron/mediamtx/releases) and run it. WHIP/WHEP listens on `:8889` by default.
   / 从 [releases](https://github.com/bluenviron/mediamtx/releases) 下载对应系统的 MediaMTX（单个 Go 二进制，免配置）并运行，WHIP/WHEP 默认监听 `:8889`。
2. Forward the port to the phone over USB:
   / 通过 USB 把端口映射给手机：
   ```bash
   adb reverse tcp:8889 tcp:8889
   ```
3. In the app's RTC tab the endpoints are pre-filled — just tap **join anchor** (publishes the camera via WHIP), then **subscribe** (plays it back via WHEP). You should see your own camera looped back, confirming the full WebRTC path.
   / 应用 RTC 页已预填端点——直接点 **join anchor**（经 WHIP 推摄像头），再点 **subscribe**（经 WHEP 拉回），即可看到自己摄像头原路回放，验证整条 WebRTC 链路。

> The stream name is the URL path segment (`rtc-link`); the `?stream=` query the plugin appends is ignored by MediaMTX. Both WHIP and WHEP URLs must share the same path segment for the loopback to match.
> / 流名即 URL 路径段（`rtc-link`）；插件追加的 `?stream=` 查询会被 MediaMTX 忽略。WHIP 与 WHEP 路径段必须一致，回环才能对上。

To use a different server (SRS / ZLMediaKit / a remote MediaMTX), just edit the `whip url` / `whep url` fields in the UI.
/ 若要换用其它服务器（SRS / ZLMediaKit / 远程 MediaMTX），直接在界面里改 `whip url` / `whep url` 即可。

## Known issues / 已知问题

### `FilePickerPlugin` not found on AGP 9 hosts / AGP 9 宿主下找不到 FilePickerPlugin

**Symptom / 现象:** building the example on a host using Android Gradle Plugin 9 (the default in recent Flutter templates, e.g. AGP 9.1.0 with `compileSdk 36`) fails with an error such as `error: cannot find symbol FilePickerPlugin` or "unable to find class `com.mr.flutter.plugin.filepicker.FilePickerPlugin`".

**Root cause / 根因:** `file_picker 11.0.3` (pulled in transitively by `flutter_ota`) declares its Android `build.gradle` to **skip the Kotlin Gradle Plugin when AGP >= 9**, assuming AGP 9's built-in Kotlin would compile its `.kt` sources. It does not, so `FilePickerPlugin.kt` is never compiled and the class is missing. `file_picker 13.x` moved the Android implementation out of the main package, so upgrading does not help either.

**Local workaround (per build machine) / 本地 workaround（每台构建机）:** force `file_picker` to compile its Kotlin sources on AGP 9 by editing the package in your **local pub cache**:

```text
# Windows (adjust the path to your pub cache)
D:\Flutter\pub-cache\hosted\pub.flutter-io.cn\file_picker-11.0.3\android\build.gradle

# change the AGP version guard to a constant false so KGP is always applied
def isAgp9OrAbove = false   # originally: ... >= 9
```

Then re-resolve and rebuild:

```bash
flutter pub get
flutter run
```

> ⚠️ This edits the **global pub cache**, not the repository, so it is not committed and is lost after `flutter pub cache repair` or clearing the cache. Re-apply the one-line change when that happens.

**Proper fix / 真正修复:** this is an upstream issue in `file_picker` / `flutter_ota`. A clean, repo-level fix requires an upstream release that compiles Kotlin on AGP 9 (or `flutter_ota` raising its `file_picker` constraint to such a version). It is tracked outside this example.
