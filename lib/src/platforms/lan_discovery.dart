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
    late Discovery discovery;
    late void Function(Service, ServiceStatus) listener;
    final controller = StreamController<LanService>(
      onCancel: () async {
        discovery.removeServiceListener(listener);
        await stopDiscovery(discovery);
      },
    );
    () async {
      discovery = await startDiscovery(
        serviceType,
        autoResolve: true,
        ipLookupType: ipLookupType,
      );
      listener = (service, status) {
        if (status != ServiceStatus.found || controller.isClosed) return;
        controller.add(
          LanService(
            name: service.name,
            host: service.host,
            port: service.port,
            addresses:
                service.addresses?.map((address) => address.address).toList() ??
                const <String>[],
          ),
        );
      };
      discovery.addServiceListener(listener);
    }();
    return controller.stream;
  }
}
