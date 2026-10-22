import 'dart:async';

import 'package:flutter/services.dart';

import '../core/rtc_events.dart';

/// Method-channel wrapper for the plugin's native modules (DPP, foreground
/// service). / 插件原生模块（DPP、前台服务）的 MethodChannel 封装。
///
/// Channel prefix is `com.zerolabsco.rtc_link/`; method names are snake_case
/// and error codes come from [RtcErrorCodes]. All native results are delivered
/// on the main thread. / Channel 前缀为 `com.zerolabsco.rtc_link/`；方法名
/// snake_case，错误码取自 [RtcErrorCodes]。原生结果全部回主线程。
class RtcLinkPlatform {
  RtcLinkPlatform._();

  /// Singleton. / 单例。
  static final RtcLinkPlatform instance = RtcLinkPlatform._();

  static const MethodChannel _methods = MethodChannel(
    'com.zerolabsco.rtc_link/methods',
  );

  static const EventChannel _events = EventChannel(
    'com.zerolabsco.rtc_link/events',
  );

  /// Whether the current platform supports DPP (Wi-Fi Easy Connect).
  /// 当前平台是否支持 DPP（Wi-Fi Easy Connect）。
  Future<bool> isDppSupported() async {
    try {
      return await _methods.invokeMethod<bool>('dppSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw RtcException(
        code: RtcErrorCodes.nativeError,
        message: 'dppSupported failed: ${e.message}',
        cause: e,
      );
    }
  }

  /// Starts the system DPP configurator with the scanned QR content
  /// (Android 10+ only). / 用扫描到的二维码内容启动系统 DPP 配置器（仅 Android 10+）。
  Future<bool> startDppConfigurator(String qrContent) async {
    try {
      return await _methods.invokeMethod<bool>('dppStart', <String, dynamic>{
            'qrContent': qrContent,
          }) ??
          false;
    } on MissingPluginException catch (e) {
      throw RtcException(
        code: RtcErrorCodes.unsupported,
        message: 'DPP is not available on this platform (Android 10+ only).',
        cause: e,
      );
    } on PlatformException catch (e) {
      throw RtcException(
        code: RtcErrorCodes.nativeError,
        message: 'dppStart failed: ${e.message}',
        cause: e,
      );
    }
  }

  /// Starts the microphone foreground service so background capture survives
  /// app suspension (Android 14+ hard requirement). / 启动麦克风前台服务，
  /// 使后台采集在应用挂起后继续（Android 14+ 硬性要求）。
  Future<void> startForegroundService({
    required String title,
    required String text,
  }) async {
    try {
      await _methods.invokeMethod<void>(
        'foregroundServiceStart',
        <String, dynamic>{'title': title, 'text': text},
      );
    } on MissingPluginException catch (e) {
      throw RtcException(
        code: RtcErrorCodes.unsupported,
        message: 'Foreground service is Android-only.',
        cause: e,
      );
    } on PlatformException catch (e) {
      throw RtcException(
        code: RtcErrorCodes.nativeError,
        message: 'foregroundServiceStart failed: ${e.message}',
        cause: e,
      );
    }
  }

  /// Stops the microphone foreground service. / 停止麦克风前台服务。
  Future<void> stopForegroundService() async {
    try {
      await _methods.invokeMethod<void>('foregroundServiceStop');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      throw RtcException(
        code: RtcErrorCodes.nativeError,
        message: 'foregroundServiceStop failed: ${e.message}',
        cause: e,
      );
    }
  }

  /// Native event stream (DPP progress, foreground-service state).
  /// 原生事件流（DPP 进度、前台服务状态）。
  Stream<Map<String, dynamic>> get nativeEvents {
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{'type': 'unknown'};
    });
  }
}
