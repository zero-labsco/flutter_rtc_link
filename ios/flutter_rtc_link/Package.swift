// swift-tools-version: 5.9
//
// Flutter RTC Link — iOS native sources as a Swift package.
// Flutter RTC Link —— 以 Swift 包形式提供的 iOS 原生源码。
//
// CocoaPods support is retained (ios/flutter_rtc_link.podspec) because Flutter
// requires plugins to support both until further notice.
// 仍保留 CocoaPods 支持（ios/flutter_rtc_link.podspec），因为 Flutter 要求插件
// 暂时同时支持两者。
import PackageDescription

let package = Package(
    name: "flutter_rtc_link",
    platforms: [
        // NFC NDEF read/write needs iOS 13+; most NDEF features are iOS 15+.
        // NFC NDEF 读写需要 iOS 13+；多数 NDEF 特性在 iOS 15+ 才完整。
        .iOS("15.0")
    ],
    products: [
        // The plugin name contains "_", so the library name uses "-" separators.
        // 插件名含 "_"，库名使用 "-" 分隔。
        .library(name: "flutter-rtc-link", targets: ["flutter_rtc_link"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_rtc_link",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
