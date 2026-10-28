import 'package:flutter_rtc_link/flutter_rtc_link_device.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// [WifiNetworkConnector] implementation built on `wifi_iot`.
/// 基于 `wifi_iot` 实现的 [WifiNetworkConnector]。
///
/// The plugin ships the abstraction only — joining Wi-Fi networks is the app's
/// decision, and this is where the demo does it.
/// 插件只提供抽象——连接 Wi-Fi 由应用决定，本文件就是演示应用接线的地方。
class WifiIotConnector implements WifiNetworkConnector {
  const WifiIotConnector();

  @override
  Future<bool> connectToOpenNetwork(
    String ssid, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return WiFiForIoTPlugin.connect(
      ssid,
      security: NetworkSecurity.NONE,
      joinOnce: true,
      withInternet: false,
      timeoutInSeconds: timeout.inSeconds,
    );
  }
}
