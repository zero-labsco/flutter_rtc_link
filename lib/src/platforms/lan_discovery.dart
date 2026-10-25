import 'dart:async';

import 'package:nsd/nsd.dart';

/// A discovered LAN service. / 发现的局域网服务。
class LanService {
  const LanService({
    this.name,
    this.host,
    this.port,
    this.addresses = const <String>[],
  });

  /// Service name. / 服务名。
  final String? name;

  /// Host name. / 主机名。
  final String? host;

  /// Port. / 端口。
  final int? port;

  /// Resolved IP addresses. / 解析出的 IP 地址。
  final List<String> addresses;

  /// Builds a reachable URL when host and port are known. / 主机与端口已知时构造可达 URL。
  Uri? get url {
    final host = this.host;
    final port = this.port;
    if (host == null || port == null) return null;
    return Uri(scheme: 'http', host: host, port: port);
  }
}

/// mDNS / DNS-SD discovery for devices and self-hosted media services.
/// 面向设备与自建媒体服务的 mDNS / DNS-SD 发现。
class LanDiscovery {
  const LanDiscovery._();

  /// Discovers services for [timeout] and returns the resolved list.
  /// 发现 [timeout] 时长的服务并返回解析后的列表。
  static Future<List<LanService>> discover({
    required String serviceType,
    Duration timeout = const Duration(seconds: 5),
    IpLookupType ipLookupType = IpLookupType.any,
  }) async {
    final found = <String, LanService>{};
    final discovery = await startDiscovery(
      serviceType,
      autoResolve: true,
      ipLookupType: ipLookupType,
    );
    void listener(Service service, ServiceStatus status) {
      if (status != ServiceStatus.found) return;
      found['${service.name ?? ''}-${service.type ?? ''}'] = LanService(
        name: service.name,
        host: service.host,
        port: service.port,
        addresses:
            service.addresses?.map((address) => address.address).toList() ??
            const <String>[],
      );
    }

    discovery.addServiceListener(listener);
    for (final service in discovery.services) {
      listener(service, ServiceStatus.found);
    }
    await Future<void>.delayed(timeout);
    discovery.removeServiceListener(listener);
    await stopDiscovery(discovery);
    return found.values.toList();
  }

  /// Continuous discovery stream (found services only). / 连续发现流（仅新发现的服务）。
  static Stream<LanService> discoverStream(
    String serviceType, {
    IpLookupType ipLookupType = IpLookupType.any,
  }) {
    Discovery? discovery;
    void Function(Service, ServiceStatus)? listener;
    // Set when the subscriber leaves before startDiscovery() has returned: the
    // onCancel callback below cannot stop a discovery it has not seen yet. /
    // 订阅者在 startDiscovery() 返回之前离开时置位：下面的 onCancel 无法停止一个
    // 它还没拿到的 discovery。
    var cancelled = false;
    final controller = StreamController<LanService>(
      onCancel: () async {
        cancelled = true;
        if (discovery != null && listener != null) {
          discovery!.removeServiceListener(listener!);
        }
        if (discovery != null) await stopDiscovery(discovery!);
      },
    );
    () async {
      try {
        final started = await startDiscovery(
          serviceType,
          autoResolve: true,
          ipLookupType: ipLookupType,
        );
        // Cancelled while we were starting: stop it now, otherwise this
        // discovery is never stopped. / 启动期间被取消：立即停止，否则该
        // discovery 永远不会停止。
        if (cancelled) {
          await stopDiscovery(started);
          return;
        }
        listener = (service, status) {
          if (status != ServiceStatus.found || controller.isClosed) return;
          controller.add(
            LanService(
              name: service.name,
              host: service.host,
              port: service.port,
              addresses:
                  service.addresses
                      ?.map((address) => address.address)
                      .toList() ??
                  const <String>[],
            ),
          );
        };
        started.addServiceListener(listener!);
        discovery = started;
      } catch (e, s) {
        // Surface the failure instead of losing it inside this fire-and-forget
        // future, which also left subscribers hanging forever. /
        // 上报失败，而不是让它在 fire-and-forget 的 future 中丢失——那还会让订阅者
        // 永久挂起。
        if (!controller.isClosed) {
          controller.addError(e, s);
          await controller.close();
        }
      }
    }();
    return controller.stream;
  }
}
