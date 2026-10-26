import 'dart:async';

/// Kind of the network path currently used by the device.
/// 设备当前所用网络路径的类型。
enum NetworkKind {
  /// No usable network. / 无可用网络。
  none,

  /// Wi-Fi. / Wi-Fi。
  wifi,

  /// Cellular (2G/3G/4G/5G). / 蜂窝网络（2G / 3G / 4G / 5G）。
  cellular,

  /// Wired Ethernet (docks, industrial gateways). / 有线以太网（扩展坞、工业网关）。
  ethernet,

  /// Anything else (VPN, bluetooth tethering, …). / 其他（VPN、蓝牙共享等）。
  other,
}

/// A concrete network path. / 一条具体的网络路径。
///
/// [generation] changes whenever the device moves to a different link even if
/// the kind stays the same (new SSID, AP roaming, new cell tower). It is the
/// only reliable way to detect a handover that ICE must react to.
/// 即使类型不变，只要设备切到另一条链路（换 SSID、AP 漫游、换基站），
/// [generation] 就会变化。这是检测 ICE 必须响应的切换的唯一可靠方式。
class NetworkPath {
  const NetworkPath({
    required this.kind,
    this.metered = false,
    this.generation = 0,
    this.label,
    this.since,
  });

  /// Unknown / not yet probed path. / 未知 / 尚未探测的路径。
  const NetworkPath.unknown()
    : kind = NetworkKind.other,
      metered = false,
      generation = 0,
      label = null,
      since = null;

  /// Path kind. / 路径类型。
  final NetworkKind kind;

  /// Whether the path is metered (cellular tethering, paid hotspot).
  /// 该路径是否按流量计费（蜂窝共享、付费热点）。
  final bool metered;

  /// Link generation (bumped on every link change). / 链路代次（每次链路变化递增）。
  final int generation;

  /// Human-readable detail (SSID, carrier name). / 可读细节（SSID、运营商名）。
  final String? label;

  /// When this path was observed. / 该路径的观测时间。
  final DateTime? since;

  /// Whether the path can carry media at all. / 该路径是否能承载媒体。
  bool get isUsable => kind != NetworkKind.none;

  /// Whether the path is unknown (never probed). / 路径是否未知（从未探测）。
  bool get isUnknown => since == null;

  /// True when both paths describe the very same link. / 两条路径是否描述的是同一条链路。
  ///
  /// A metered flip (Wi-Fi hotspot that started charging, cellular that turned
  /// unmetered) is a different link for policy purposes, so it counts too.
  /// 计费状态翻转（Wi-Fi 热点开始计费、蜂窝变为不计流量）在策略上是另一条链路，
  /// 因此也计入比较。
  bool isSameLinkAs(NetworkPath other) =>
      kind == other.kind &&
      generation == other.generation &&
      metered == other.metered;

  /// Copies with the given fields replaced. / 复制并替换给定字段。
  NetworkPath copyWith({
    NetworkKind? kind,
    bool? metered,
    int? generation,
    String? label,
    DateTime? since,
  }) {
    return NetworkPath(
      kind: kind ?? this.kind,
      metered: metered ?? this.metered,
      generation: generation ?? this.generation,
      label: label ?? this.label,
      since: since ?? this.since,
    );
  }

  /// Serializes for diagnostics reports. / 序列化以供诊断报告使用。
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.name,
    'metered': metered,
    'generation': generation,
    if (label != null) 'label': label,
    if (since != null) 'since': since!.toIso8601String(),
  };

  @override
  String toString() =>
      'NetworkPath(${kind.name}${label == null ? '' : '/$label'}, gen $generation)';
}

/// A path transition. / 一次路径变迁。
class NetworkPathChange {
  const NetworkPathChange({required this.from, required this.to});

  /// Previous path. / 变化前的路径。
  final NetworkPath from;

  /// New path. / 变化后的路径。
  final NetworkPath to;

  /// Whether anything relevant changed. / 是否有相关变化。
  bool get hasChange => !from.isSameLinkAs(to);

  /// Whether the kind changed (Wi-Fi ↔ cellular). / 类型是否变化（Wi-Fi ↔ 蜂窝）。
  bool get kindChanged => from.kind != to.kind;

  /// Whether the device just lost every path. / 设备是否刚刚失去所有路径。
  bool get isLost => from.isUsable && !to.isUsable;

  /// Whether a path came back after being lost. / 失联后是否恢复了路径。
  bool get isRestored => !from.isUsable && to.isUsable;

  /// Whether the switch went to a metered path. / 是否切换到了按流量计费的路径。
  bool get becameMetered => !from.metered && to.metered;

  /// Whether ICE must be restarted for this change.
  /// 该变化是否需要重启 ICE。
  ///
  /// A kind change (Wi-Fi ↔ cellular) always invalidates the candidate pairs,
  /// so ICE must be restarted. Same-kind changes (roaming between APs) only
  /// when the caller opts in through [restartOnSameKind].
  /// 类型变化（Wi-Fi ↔ 蜂窝）必然使候选对失效，必须重启 ICE；同类型变化
  /// （AP 间漫游）仅在调用方通过 [restartOnSameKind] 显式开启时才重启。
  bool requiresIceRestart({bool restartOnSameKind = false}) {
    if (!hasChange) return false;
    if (!from.isUsable || !to.isUsable) return false;
    if (kindChanged) return true;
    return restartOnSameKind;
  }

  @override
  String toString() => 'NetworkPathChange($from -> $to)';
}

/// Source of network-path updates. / 网络路径更新的来源。
///
/// The plugin does not depend on a connectivity plugin: the app wires whatever
/// it already uses (`connectivity_plus`, a platform channel, or its own
/// reachability probe) into [CallbackNetworkMonitor.update].
/// 插件本身不依赖任何连通性插件：应用把已有的数据源（`connectivity_plus`、
/// 平台通道或自建可达性探测）接到 [CallbackNetworkMonitor.update] 即可。
abstract class NetworkPathMonitor {
  /// Stream of observed paths (only real changes are emitted).
  /// 观测到的路径流（仅在真正变化时投递）。
  Stream<NetworkPath> get paths;

  /// Last observed path. / 最近观测到的路径。
  NetworkPath get current;

  /// Starts observing. / 开始观测。
  Future<void> start();

  /// Stops observing. / 停止观测。
  Future<void> stop();

  /// Releases resources. / 释放资源。
  Future<void> dispose();

  /// Wraps an external stream of paths (e.g. a mapped `connectivity_plus`
  /// stream). / 包装外部路径流（如映射后的 `connectivity_plus` 流）。
  static NetworkPathMonitor fromStream(
    Stream<NetworkPath> source, {
    NetworkPath initial = const NetworkPath.unknown(),
  }) => _StreamedNetworkPathMonitor(source, initial);
}

/// Monitor driven by explicit [update] calls. / 由显式 [update] 调用驱动的监测器。
class CallbackNetworkMonitor implements NetworkPathMonitor {
  CallbackNetworkMonitor({NetworkPath initial = const NetworkPath.unknown()})
    : _current = initial;

  final StreamController<NetworkPath> _ctrl =
      StreamController<NetworkPath>.broadcast();
  NetworkPath _current;
  bool _started = false;

  @override
  Stream<NetworkPath> get paths => _ctrl.stream;

  @override
  NetworkPath get current => _current;

  /// Whether the monitor is started. / 监测器是否已启动。
  bool get isStarted => _started;

  /// Pushes a freshly observed path. Ignored when nothing relevant changed.
  /// 推送一条新观测到的路径；无相关变化则忽略。
  void update(NetworkPath path) {
    if (path.isSameLinkAs(_current)) return;
    final from = _current;
    _current = path;
    if (!_ctrl.isClosed) _ctrl.add(path);
    _lastChange = NetworkPathChange(from: from, to: path);
  }

  NetworkPathChange? _lastChange;

  /// Last classified change, if any. / 最近一次分类过的变化（如有）。
  NetworkPathChange? get lastChange => _lastChange;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
  }

  @override
  Future<void> dispose() async {
    _started = false;
    await _ctrl.close();
  }
}

class _StreamedNetworkPathMonitor implements NetworkPathMonitor {
  _StreamedNetworkPathMonitor(this._source, NetworkPath initial)
    : _current = initial;

  final Stream<NetworkPath> _source;
  NetworkPath _current;
  StreamSubscription<NetworkPath>? _sub;

  @override
  Stream<NetworkPath> get paths => _ctrl.stream;

  final StreamController<NetworkPath> _ctrl =
      StreamController<NetworkPath>.broadcast();

  @override
  NetworkPath get current => _current;

  @override
  Future<void> start() async {
    _sub ??= _source.listen((path) {
      if (path.isSameLinkAs(_current)) return;
      _current = path;
      if (!_ctrl.isClosed) _ctrl.add(path);
    });
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
  }
}
