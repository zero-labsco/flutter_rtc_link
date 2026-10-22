import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/rtc_session.dart';
import '../core/rtc_stats.dart';
import 'log_collector.dart';

/// Network probe target (TURN server, MQTT broker, device, …).
/// 网络探测目标（TURN 服务器、MQTT broker、设备等）。
class NetworkProbeTarget {
  const NetworkProbeTarget({
    required this.host,
    required this.port,
    this.secure = false,
    this.label,
  });

  final String host;
  final int port;

  /// Whether to wrap the socket in TLS. / 是否包装 TLS。
  final bool secure;

  /// Human label (defaults to `host:port`). / 可读标签（默认 `host:port`）。
  final String? label;

  String get displayLabel => label ?? '$host:$port';
}

/// Result of probing one target. / 单个目标的探测结果。
class NetworkProbeResult {
  const NetworkProbeResult({
    required this.target,
    required this.reachable,
    this.rttMs = 0,
    this.error,
  });

  final NetworkProbeTarget target;

  /// Whether the endpoint accepted a connection. / 端点是否接受连接。
  final bool reachable;

  /// Round-trip time in milliseconds. / 往返时延（毫秒）。
  final double rttMs;

  final String? error;
}

/// Verdict of the combined diagnosis. / 综合诊断结论。
enum DiagnosisVerdict {
  /// The network path is the problem (TURN/MQTT unreachable, high RTT/loss).
  /// 问题在网络侧（TURN / MQTT 不可达，高 RTT / 丢包）。
  network,

  /// The device is the problem (device-side errors in logs).
  /// 问题在设备侧（日志中出现设备错误）。
  device,

  /// Both sides show problems. / 两侧都有问题。
  both,

  /// Not enough signal to tell. / 信号不足，无法判定。
  unknown,
}

/// One-tap diagnostics report (JSON + Markdown). / 一键诊断报告（JSON + Markdown）。
class DiagnosticReport {
  const DiagnosticReport({
    required this.generatedAt,
    required this.sessionId,
    required this.rtcStats,
    required this.probes,
    required this.deviceLogs,
    required this.verdict,
    required this.reasons,
  });

  final DateTime generatedAt;
  final String? sessionId;

  /// Sampled RTC stats. / 采样的 RTC stats。
  final List<RtcStats> rtcStats;

  /// Network probe results. / 网络探测结果。
  final List<NetworkProbeResult> probes;

  /// Recent device logs (may be empty). / 最近的设备日志（可为空）。
  final List<DeviceLogEntry> deviceLogs;

  final DiagnosisVerdict verdict;

  /// Human-readable reasons behind [verdict]. / [verdict] 背后的人读原因。
  final List<String> reasons;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'generatedAt': generatedAt.toIso8601String(),
    'sessionId': sessionId,
    'verdict': verdict.name,
    'reasons': reasons,
    'rtcStats': rtcStats.map((s) => s.toJson()).toList(),
    'probes': probes
        .map(
          (p) => <String, dynamic>{
            'target': p.target.displayLabel,
            'reachable': p.reachable,
            'rttMs': p.rttMs,
            if (p.error != null) 'error': p.error,
          },
        )
        .toList(),
    'deviceLogs': deviceLogs.map((e) => e.toJson()).toList(),
  };

  /// Renders the report as Markdown. / 将报告渲染为 Markdown。
  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# RTC Link Diagnostics Report')
      ..writeln()
      ..writeln('- Generated: ${generatedAt.toIso8601String()}')
      ..writeln('- Session: ${sessionId ?? 'n/a'}')
      ..writeln('- Verdict: **${verdict.name}**')
      ..writeln()
      ..writeln('## Reasons')
      ..writeln();
    if (reasons.isEmpty) {
      buffer.writeln('- none');
    } else {
      for (final reason in reasons) {
        buffer.writeln('- $reason');
      }
    }
    buffer.writeln();
    buffer.writeln('## Network Probes');
    buffer.writeln();
    buffer.writeln('| Target | Reachable | RTT (ms) | Error |');
    buffer.writeln('| --- | --- | --- | --- |');
    for (final probe in probes) {
      buffer.writeln(
        '| ${probe.target.displayLabel} | ${probe.reachable ? 'yes' : 'no'} | '
        '${probe.rttMs.toStringAsFixed(1)} | ${probe.error ?? '-'} |',
      );
    }
    buffer.writeln();
    buffer.writeln('## RTC Stats');
    buffer.writeln();
    if (rtcStats.isEmpty) {
      buffer.writeln('No stats sampled.');
    } else {
      buffer.writeln(
        '| Stream | Kind | Bitrate (kbps) | Loss (%) | RTT (ms) | FPS | Resolution |',
      );
      buffer.writeln('| --- | --- | --- | --- | --- | --- | --- |');
      for (final stats in rtcStats) {
        buffer.writeln(
          '| ${stats.streamId} | ${stats.kind.name} | '
          '${stats.bitrateKbps.toStringAsFixed(0)} | '
          '${stats.packetLossPercent.toStringAsFixed(1)} | '
          '${stats.rttMs.toStringAsFixed(0)} | ${stats.fps.toStringAsFixed(0)} | '
          '${stats.width}x${stats.height} |',
        );
      }
    }
    buffer.writeln();
    buffer.writeln('## Device Logs (last ${deviceLogs.length})');
    buffer.writeln();
    for (final entry in deviceLogs) {
      buffer.writeln(
        '- [${entry.timestamp.toIso8601String()}] ${entry.level.name} '
        '${entry.tag}: ${entry.message}',
      );
    }
    return buffer.toString();
  }
}

/// TCP / TLS reachability probe. / TCP / TLS 可达性探测。
class NetworkProbe {
  NetworkProbe({
    required this.targets,
    this.timeout = const Duration(seconds: 5),
  });

  final List<NetworkProbeTarget> targets;
  final Duration timeout;

  /// Probes every target. / 探测所有目标。
  Future<List<NetworkProbeResult>> run() async {
    if (kIsWeb) {
      return targets
          .map(
            (t) => NetworkProbeResult(
              target: t,
              reachable: false,
              error: 'raw sockets are not available on web',
            ),
          )
          .toList();
    }
    final results = <NetworkProbeResult>[];
    for (final target in targets) {
      results.add(await _probe(target));
    }
    return results;
  }

  Future<NetworkProbeResult> _probe(NetworkProbeTarget target) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        target.host,
        target.port,
        timeout: timeout,
      );
      if (target.secure) {
        final secure = await SecureSocket.secure(socket, host: target.host);
        secure.destroy();
      } else {
        socket.destroy();
      }
      stopwatch.stop();
      return NetworkProbeResult(
        target: target,
        reachable: true,
        rttMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e) {
      stopwatch.stop();
      return NetworkProbeResult(
        target: target,
        reachable: false,
        rttMs: stopwatch.elapsedMilliseconds.toDouble(),
        error: e.toString(),
      );
    }
  }
}

/// Diagnostics entry point. / 诊断入口。
///
/// Aggregates WebRTC stats, network reachability and device logs, then
/// classifies the failure so the report answers "is video stuttering caused by
/// TURN being blocked or by the device's CPU?" — not just "something is wrong".
/// 聚合 WebRTC stats、网络可达性与设备日志并给出分类，让报告回答
/// "视频卡顿是 TURN 不通还是设备 CPU 高？"——而非笼统的"有问题"。
class Diagnostics {
  const Diagnostics._();

  /// Runs diagnostics and builds the report. / 运行诊断并生成报告。
  static Future<DiagnosticReport> run({
    RtcSession? session,
    NetworkProbe? networkProbe,
    DeviceLogCollector? deviceLogs,
    String? sessionId,
    Duration sampleWindow = const Duration(seconds: 2),
    int maxLogEntries = 100,
  }) async {
    final stats = <RtcStats>[];
    if (session != null) {
      final subscription = session.stats.listen(stats.add);
      await Future<void>.delayed(sampleWindow);
      await subscription.cancel();
    }
    final probes =
        await (networkProbe?.run() ??
            Future<List<NetworkProbeResult>>.value(
              const <NetworkProbeResult>[],
            ));
    final logs = deviceLogs == null
        ? const <DeviceLogEntry>[]
        : await deviceLogs
              .collectCrashBundle(lastN: maxLogEntries)
              .then(
                (bundle) => (bundle['logs'] as List<dynamic>)
                    .whereType<Map<String, dynamic>>()
                    .map(DeviceLogEntry.fromJson)
                    .whereType<DeviceLogEntry>()
                    .toList(),
              );
    final (verdict, reasons) = _classify(stats, probes, logs);
    return DiagnosticReport(
      generatedAt: DateTime.now(),
      sessionId: sessionId ?? session?.roomId,
      rtcStats: stats,
      probes: probes,
      deviceLogs: logs,
      verdict: verdict,
      reasons: reasons,
    );
  }

  static (DiagnosisVerdict, List<String>) _classify(
    List<RtcStats> stats,
    List<NetworkProbeResult> probes,
    List<DeviceLogEntry> logs,
  ) {
    final reasons = <String>[];
    var networkProblem = false;
    var deviceProblem = false;

    for (final probe in probes) {
      if (!probe.reachable) {
        networkProblem = true;
        reasons.add(
          '${probe.target.displayLabel} is unreachable'
          '${probe.error != null ? ' (${probe.error})' : ''}.',
        );
      } else if (probe.rttMs > 200) {
        networkProblem = true;
        reasons.add(
          '${probe.target.displayLabel} RTT is ${probe.rttMs.toStringAsFixed(0)}ms.',
        );
      }
    }

    for (final sample in stats) {
      if (sample.rttMs > 300 || sample.packetLossPercent > 10) {
        networkProblem = true;
        reasons.add(
          'Stream ${sample.streamId}: RTT ${sample.rttMs.toStringAsFixed(0)}ms, '
          'loss ${sample.packetLossPercent.toStringAsFixed(1)}%.',
        );
      }
    }

    final deviceErrors = logs.where((l) => l.level == LogLevel.error).length;
    if (deviceErrors > 0) {
      deviceProblem = true;
      reasons.add('Device logs contain $deviceErrors error-level entries.');
    }

    if (networkProblem && deviceProblem) {
      return (DiagnosisVerdict.both, reasons);
    }
    if (networkProblem) return (DiagnosisVerdict.network, reasons);
    if (deviceProblem) return (DiagnosisVerdict.device, reasons);
    if (stats.isEmpty && probes.isEmpty && logs.isEmpty) {
      return (
        DiagnosisVerdict.unknown,
        <String>['No diagnostics input provided.'],
      );
    }
    return (DiagnosisVerdict.unknown, <String>['No problem signal detected.']);
  }
}
