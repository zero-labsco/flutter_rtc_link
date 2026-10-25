import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/rtc_events.dart';
import '../robot/teleop_channel.dart' show MqttCredentials;

/// Log level. / 日志级别。
enum LogLevel {
  /// Verbose. / 详细。
  verbose,

  /// Debug. / 调试。
  debug,

  /// Info. / 信息。
  info,

  /// Warning. / 警告。
  warning,

  /// Error. / 错误。
  error,
}

/// Device log entry. / 设备日志条目。
class DeviceLogEntry {
  const DeviceLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.deviceId,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? deviceId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'ts': timestamp.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    if (deviceId != null) 'deviceId': deviceId,
  };

  static DeviceLogEntry? fromJson(Map<String, dynamic> json) {
    final ts = DateTime.tryParse(json['ts'] as String? ?? '');
    if (ts == null) return null;
    return DeviceLogEntry(
      timestamp: ts,
      level: LogLevel.values.firstWhere(
        (l) => l.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      tag: json['tag'] as String? ?? '',
      message: json['message'] as String? ?? '',
      deviceId: json['deviceId'] as String?,
    );
  }
}

/// Uploads log batches. / 上传日志批次。
abstract class LogUploader {
  /// Uploads [entries]; returns whether the batch was accepted.
  /// 上传 [entries]；返回该批次是否被接受。
  Future<bool> upload(String deviceId, List<DeviceLogEntry> entries);
}

/// Local cache for offline batching. / 离线批量补传的本地缓存。
abstract class LogCache {
  /// Appends entries to the cache. / 追加条目到缓存。
  Future<void> append(List<DeviceLogEntry> entries);

  /// Takes up to [max] entries (removing them). / 取出最多 [max] 条（并移除）。
  Future<List<DeviceLogEntry>> take({int max = 100});

  /// Peeks at the most recent [max] entries without removing them.
  /// 查看最近 [max] 条而不移除。
  Future<List<DeviceLogEntry>> peek({int max = 200});

  /// Pending entry count. / 待处理条目数。
  Future<int> get pendingCount;

  /// Clears the cache. / 清空缓存。
  Future<void> clear();
}

/// File-based JSONL cache with rotation (system temp directory).
/// 基于文件的 JSONL 缓存，带轮转（系统临时目录）。
class FileLogCache implements LogCache {
  FileLogCache({
    required this.deviceId,
    this.maxEntries = 5000,
    String? directory,
  }) : _file = File(
         <String>[
           directory ?? Directory.systemTemp.path,
           'rtc_link_logs_$deviceId.jsonl',
         ].join(Platform.isWindows ? '\\' : '/'),
       );

  final String deviceId;
  final int maxEntries;
  final File _file;

  @override
  Future<void> append(List<DeviceLogEntry> entries) async {
    if (entries.isEmpty) return;
    final lines = entries.map((e) => jsonEncode(e.toJson())).join('\n');
    await _file.writeAsString('$lines\n', mode: FileMode.append, flush: true);
    await _rotate();
  }

  @override
  Future<List<DeviceLogEntry>> take({int max = 100}) async {
    if (!_file.existsSync()) return const <DeviceLogEntry>[];
    final lines = await _file.readAsLines();
    if (lines.isEmpty) return const <DeviceLogEntry>[];
    final taken = lines.take(max).toList();
    final rest = lines.skip(max).toList();
    await _file.writeAsString(
      rest.isEmpty ? '' : '${rest.join('\n')}\n',
      flush: true,
    );
    // Skip corrupt lines: a crash mid-write leaves a partial line, and one bad
    // line must not make the whole cache unreadable. /
    // 跳过损坏行：写入中途崩溃会留下半行，一行坏不能让整个缓存不可用。
    final entries = <DeviceLogEntry>[];
    for (final line in taken) {
      try {
        final entry = DeviceLogEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );
        if (entry != null) entries.add(entry);
      } catch (_) {
        continue;
      }
    }
    return entries;
  }

  @override
  Future<List<DeviceLogEntry>> peek({int max = 200}) async {
    if (!_file.existsSync()) return const <DeviceLogEntry>[];
    final lines = await _file.readAsLines();
    if (lines.isEmpty) return const <DeviceLogEntry>[];
    final last = lines.length <= max
        ? lines
        : lines.sublist(lines.length - max);
    // Same corruption guard as take(). / 与 take() 相同的损坏行保护。
    final entries = <DeviceLogEntry>[];
    for (final line in last) {
      try {
        final entry = DeviceLogEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        );
        if (entry != null) entries.add(entry);
      } catch (_) {
        continue;
      }
    }
    return entries;
  }

  @override
  Future<int> get pendingCount async {
    if (!_file.existsSync()) return 0;
    final lines = await _file.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }

  @override
  Future<void> clear() async {
    if (_file.existsSync()) await _file.delete();
  }

  Future<void> _rotate() async {
    if (!_file.existsSync()) return;
    final lines = await _file.readAsLines();
    if (lines.length <= maxEntries) return;
    final kept = lines.sublist(lines.length - maxEntries);
    await _file.writeAsString('${kept.join('\n')}\n', flush: true);
  }
}

/// MQTT log uploader (QoS 1, TLS-capable). / MQTT 日志上传器（QoS 1，支持 TLS）。
class MqttLogUploader implements LogUploader {
  MqttLogUploader({
    required this.broker,
    required this.topic,
    this.credentials,
    this.qos = MqttQos.atLeastOnce,
  });

  final String broker;
  final String topic;
  final Future<MqttCredentials?> Function()? credentials;
  final MqttQos qos;

  MqttServerClient? _client;

  @override
  Future<bool> upload(String deviceId, List<DeviceLogEntry> entries) async {
    if (entries.isEmpty) return true;
    final client = await _ensureConnected(deviceId);
    if (client == null) return false;
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(
        jsonEncode(<String, dynamic>{
          'deviceId': deviceId,
          'logs': entries.map((e) => e.toJson()).toList(),
        }),
      );
      client.publishMessage(topic, qos, builder.payload!);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<MqttServerClient?> _ensureConnected(String deviceId) async {
    final existing = _client;
    if (existing != null &&
        existing.connectionStatus?.state == MqttConnectionState.connected) {
      return existing;
    }
    // Drop the previous client before replacing it: mqtt_client keeps its
    // socket and broker session alive otherwise. /
    // 替换前先丢弃旧 client：否则 mqtt_client 会保留其 socket 与 broker 会话。
    if (existing != null) {
      try {
        existing.disconnect();
      } catch (_) {
        // Best effort. / 尽力而为。
      }
      _client = null;
    }
    final uri = Uri.parse(broker);
    final client = MqttServerClient(
      uri.host,
      'rtc-link-log-$deviceId-${DateTime.now().microsecondsSinceEpoch}',
    );
    client.port = uri.hasPort
        ? uri.port
        : (uri.scheme == 'mqtts' ? 8883 : 1883);
    client.secure = uri.scheme == 'mqtts';
    client.keepAlivePeriod = 30;
    client.logging(on: false);
    final creds = await credentials?.call();
    try {
      await client.connect(creds?.username, creds?.password);
    } catch (_) {
      client.disconnect();
      return null;
    }
    // connect() reports failures through connectionStatus instead of throwing,
    // so an unchecked client would silently swallow every log batch while
    // still reporting success. / connect() 通过 connectionStatus 而非抛异常来
    // 报告失败，因此不检查会让每批日志被静默吞掉却仍上报成功。
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      return null;
    }
    _client = client;
    return client;
  }

  /// Disconnects the uploader. / 断开上传器。
  Future<void> dispose() async {
    _client?.disconnect();
    _client = null;
  }
}

/// Masks emails, phone numbers and long tokens in log text (privacy).
/// 对日志文本中的邮箱、手机号与长令牌做脱敏（隐私）。
String redactSensitiveData(String input) {
  var output = input.replaceAll(
    RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
    '***@***',
  );
  output = output.replaceAll(
    RegExp(r'(?<!\d)(?:\+?\d{1,3}[- ]?)?\d{11}(?!\d)'),
    '***********',
  );
  // `replaceAll` does not expand `$1` group references — `replaceAllMapped`
  // does, so the key name is preserved while the value is masked.
  // `replaceAll` 不会展开 `$1` 分组引用——`replaceAllMapped` 才会，
  // 因此保留键名、遮蔽取值。
  output = output.replaceAllMapped(
    RegExp(
      r'\b(bearer|token|password|passwd|secret)\s*[:=]\s*\S+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}: ***',
  );
  return output;
}

/// Device log collector: local cache + batch upload + crash bundling.
/// 设备日志采集器：本地缓存 + 批量上传 + 崩溃现场打包。
class DeviceLogCollector {
  DeviceLogCollector({
    LogUploader? uploader,
    LogCache? cache,
    this.maxBatchSize = 100,
    this.flushInterval = const Duration(seconds: 30),
    this.keywordFilter,
    this.redactSensitive = true,
    String? deviceId,
    Logger? logger,
  }) : _uploader = uploader,
       _cache = cache,
       _deviceId = deviceId,
       _logger = logger ?? Logger('DeviceLogCollector');

  final LogUploader? _uploader;
  final LogCache? _cache;
  final String? _deviceId;
  final Logger _logger;

  /// Max entries per batch. / 每批最大条目数。
  final int maxBatchSize;

  /// Auto-flush interval. / 自动刷写间隔。
  final Duration flushInterval;

  /// Optional keyword filter (only matching entries are kept). / 可选关键字过滤（仅保留匹配条目）。
  final RegExp? keywordFilter;

  /// Redact sensitive data before storing/uploading. / 存储 / 上传前脱敏。
  final bool redactSensitive;

  final StreamController<DeviceEvent> _eventsCtrl =
      StreamController<DeviceEvent>.broadcast();
  final List<DeviceLogEntry> _buffer = <DeviceLogEntry>[];
  Timer? _flushTimer;
  String? _activeDeviceId;
  bool _flushing = false;
  LogLevel _level = LogLevel.debug;

  /// Device events (batch uploads). / 设备事件（批量上传）。
  Stream<DeviceEvent> get events => _eventsCtrl.stream;

  /// Whether collection is active. / 采集是否进行中。
  bool get isActive => _activeDeviceId != null;

  /// Starts collection for [deviceId]. / 为 [deviceId] 启动采集。
  Future<void> start({
    required String deviceId,
    LogLevel level = LogLevel.debug,
  }) async {
    _activeDeviceId = deviceId;
    _level = level;
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Appends a log entry. / 追加一条日志。
  void log(LogLevel level, String tag, String message, {String? deviceId}) {
    if (!isActive) return;
    if (level.index < _level.index) return;
    var text = message;
    if (redactSensitive) text = redactSensitiveData(text);
    final keyword = keywordFilter;
    if (keyword != null && !keyword.hasMatch(text)) return;
    _buffer.add(
      DeviceLogEntry(
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: text,
        deviceId: deviceId ?? _activeDeviceId ?? _deviceId,
      ),
    );
    if (_buffer.length >= maxBatchSize) {
      unawaited(flush());
    }
  }

  /// Flushes buffered entries: upload first, cache on failure.
  /// 刷写缓冲条目：先上传，失败则入缓存。
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    // Guard against re-entrancy: a timer-triggered flush can enter while an
    // upload is already in flight, and both would then take (and later
    // re-append) the same cached batch. /
    // 防止重入：定时器触发的 flush 会在上传进行中进入，两者会取到（并稍后重复
    // 回写）同一批缓存。
    if (_flushing) return;
    _flushing = true;
    try {
      final deviceId = _activeDeviceId ?? _deviceId ?? 'unknown';
      final batch = _buffer.take(maxBatchSize).toList();
      _buffer.removeRange(0, batch.length);
      var uploaded = false;
      final uploader = _uploader;
      if (uploader != null) {
        uploaded = await uploader.upload(deviceId, batch);
      }
      if (!uploaded) {
        final cache = _cache;
        if (cache == null) {
          // Without a cache the batch really is lost — do not claim it was
          // cached. / 没有缓存时这批日志确实丢了——不能谎称已缓存。
          _logger.warning(
            'log upload failed and no cache is configured; '
            '${batch.length} entries dropped',
          );
          return;
        }
        // Weak network: keep locally and re-send on the next flush.
        // 弱网：本地留存，下次 flush 补传。
        _logger.info(
          'log upload failed; ${batch.length} entries cached locally',
        );
        await cache.append(batch);
        return;
      }
      _eventsCtrl.add(
        LogBatchUploaded(deviceId: deviceId, count: batch.length),
      );
      await _flushCached(deviceId);
    } finally {
      _flushing = false;
    }
  }

  /// Packages the last [lastN] entries as a crash bundle.
  /// 把最近 [lastN] 条日志打包为崩溃现场。
  Future<Map<String, dynamic>> collectCrashBundle({
    int lastN = 200,
    Map<String, dynamic> deviceInfo = const <String, dynamic>{},
  }) async {
    final cached = await _cache?.peek(max: lastN) ?? const <DeviceLogEntry>[];
    final all = <DeviceLogEntry>[...cached, ..._buffer];
    final last = all.length <= lastN ? all : all.sublist(all.length - lastN);
    return <String, dynamic>{
      'deviceId': _activeDeviceId ?? _deviceId,
      'capturedAt': DateTime.now().toIso8601String(),
      'deviceInfo': deviceInfo,
      'logs': last.map((e) => e.toJson()).toList(),
    };
  }

  /// Stops collection. / 停止采集。
  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    _activeDeviceId = null;
  }

  /// Releases resources. / 释放资源。
  Future<void> dispose() async {
    await stop();
    await _eventsCtrl.close();
    final uploader = _uploader;
    if (uploader is MqttLogUploader) await uploader.dispose();
  }

  Future<void> _flushCached(String deviceId) async {
    final cache = _cache;
    final uploader = _uploader;
    if (cache == null || uploader == null) return;
    final pending = await cache.take(max: maxBatchSize);
    if (pending.isEmpty) return;
    final ok = await uploader.upload(deviceId, pending);
    if (ok) {
      _eventsCtrl.add(
        LogBatchUploaded(deviceId: deviceId, count: pending.length),
      );
    } else {
      // Put them back for the next round. / 放回缓存，下轮再传。
      await cache.append(pending);
    }
  }
}

/// Re-exported for convenience (same credentials type as the MQTT teleop
/// channel). / 便捷再导出（与 MQTT 远控通道相同的凭证类型）。
typedef LogMqttCredentials = MqttCredentials;
