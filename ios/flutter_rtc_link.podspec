#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_rtc_link.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_rtc_link'
  s.version          = '0.1.0'
  s.summary          = 'Flutter real-time audio/video (WHIP/WHEP + LiveKit) and IoT device management plugin.'
  s.description      = <<-DESC
Flutter real-time audio/video (WebRTC WHIP/WHEP + LiveKit) and IoT device management plugin: publish, subscribe, clarity switching, live relay, robot teleoperation, provisioning, OTA, logs and diagnostics.
                       DESC
  s.homepage         = 'https://github.com/zero-labsco/flutter_rtc_link'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AmisKwok' => 'amiskwok@zerolabsco.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_rtc_link/Sources/flutter_rtc_link/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Privacy manifest (required-reason API declarations live here when needed).
  # 隐私清单（需要时在此声明 required-reason API）。
  s.resource_bundles = {'flutter_rtc_link_privacy' => ['flutter_rtc_link/Sources/flutter_rtc_link/PrivacyInfo.xcprivacy']}
end
