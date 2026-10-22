# flutter_rtc_link_example

Demo app for the [`flutter_rtc_link`](https://pub.dev/packages/flutter_rtc_link) plugin: real-time audio/video (WebRTC WHIP/WHEP + LiveKit) and IoT device management — publish, subscribe, live relay, robot teleoperation, provisioning and OTA.

## Run / 运行

```bash
cd example
flutter pub get
flutter run
```

Requires a Flutter 3.35+ environment. The example targets Android `compileSdk 36` with AGP 9.1.0 by default.

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
