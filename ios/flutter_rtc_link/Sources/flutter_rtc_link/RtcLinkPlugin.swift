import Flutter
import UIKit

/// Flutter RTC Link iOS plugin entry point.
/// Flutter RTC Link iOS 插件入口。
///
/// Method channel `com.zerolabsco.rtc_link/methods` plus event channel
/// `com.zerolabsco.rtc_link/events` (same contract as Android).
/// Method channel `com.zerolabsco.rtc_link/methods` 与事件通道
/// `com.zerolabsco.rtc_link/events`（与 Android 契约一致）。
///
/// iOS reality / iOS 平台现实:
/// - DPP (Wi-Fi Easy Connect) has **no** system API on iOS — calls return a
///   typed `unsupported` error so the Dart side can degrade to BLE / NFC /
///   SoftAP guidance. / iOS 没有 DPP（Wi-Fi Easy Connect）系统 API——调用返回
///   类型化的 `unsupported` 错误，Dart 侧据此降级到 BLE / NFC / SoftAP 引导。
/// - The microphone foreground service is Android-only; iOS keeps background
///   audio alive through the host app's `UIBackgroundModes: audio` +
///   `AVAudioSession` configuration (documented in the README).
///   麦克风前台服务仅 Android 有；iOS 通过宿主 App 的
///   `UIBackgroundModes: audio` + `AVAudioSession` 配置保持后台音频
///   （见 README）。
public class RtcLinkPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methods = FlutterMethodChannel(
            name: "com.zerolabsco.rtc_link/methods",
            binaryMessenger: registrar.messenger()
        )
        let instance = RtcLinkPlugin()
        registrar.addMethodCallDelegate(instance, channel: methods)

        let events = FlutterEventChannel(
            name: "com.zerolabsco.rtc_link/events",
            binaryMessenger: registrar.messenger()
        )
        events.setStreamHandler(instance)
    }

    private var eventSink: FlutterEventSink?

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "dppSupported":
            // No system DPP on iOS. / iOS 无系统 DPP。
            result(false)

        case "dppStart":
            result(FlutterError(
                code: "unsupported",
                message: "Wi-Fi Easy Connect (DPP) is Android-only; use BLE or NFC provisioning on iOS.",
                details: nil
            ))

        case "foregroundServiceStart", "foregroundServiceStop":
            result(FlutterError(
                code: "unsupported",
                message: "Foreground services are Android-only; configure UIBackgroundModes: audio in the host app.",
                details: nil
            ))

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Event channel / 事件通道

extension RtcLinkPlugin: FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
