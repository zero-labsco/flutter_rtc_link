import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/rtc_link.dart';

import 'widgets/instrument.dart';

/// Diagnostics demo: permission gate, foreground service, one-tap report.
/// 诊断演示：权限入口、前台服务、一键报告。
class DiagnosticsDemoPage extends StatefulWidget {
  const DiagnosticsDemoPage({super.key});

  @override
  State<DiagnosticsDemoPage> createState() => _DiagnosticsDemoPageState();
}

class _DiagnosticsDemoPageState extends State<DiagnosticsDemoPage> {
  String _report = 'run diagnostics to build a report';
  final Map<RtcPermission, bool> _permissions = <RtcPermission, bool>{};

  static const List<RtcPermission> _capabilities = <RtcPermission>[
    RtcPermission.camera,
    RtcPermission.microphone,
    RtcPermission.bluetoothScan,
    RtcPermission.bluetoothConnect,
    RtcPermission.nearbyWifiDevices,
    RtcPermission.notifications,
  ];

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: <Widget>[
        const SectionLabel('permissions'),
        Panel(
          trailing: StatusChip(
            label: _permissionSummary(),
            color: _allGranted() ? status.ok : status.idle,
            active: _allGranted(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final capability in _capabilities)
                ReadoutRow(
                  label: capability.name,
                  value: switch (_permissions[capability]) {
                    true => 'granted',
                    false => 'denied',
                    null => 'unknown',
                  },
                  color: switch (_permissions[capability]) {
                    true => status.ok,
                    false => status.error,
                    null => null,
                  },
                ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: InstrumentButton(
                      label: 'request all',
                      icon: Icons.verified_user,
                      primary: true,
                      onPressed: _requestPermissions,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InstrumentButton(
                      label: 'settings',
                      icon: Icons.settings,
                      onPressed: RtcPermissions.openSettings,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionLabel('background capture'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Android 14+ needs a microphone foreground service to keep '
                'publishing while backgrounded; iOS needs the host app to '
                'enable the audio background mode.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: InstrumentButton(
                      label: 'start fgs',
                      icon: Icons.play_arrow,
                      onPressed: _startForegroundService,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InstrumentButton(
                      label: 'stop fgs',
                      icon: Icons.stop,
                      onPressed: _stopForegroundService,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionLabel('report'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InstrumentButton(
                label: 'run diagnostics',
                icon: Icons.monitor_heart,
                primary: true,
                onPressed: _runDiagnostics,
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _report,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 11, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _permissionSummary() {
    if (_permissions.isEmpty) return 'unknown';
    final granted = _permissions.values.where((v) => v).length;
    return '$granted/${_permissions.length}';
  }

  bool _allGranted() =>
      _permissions.isNotEmpty && _permissions.values.every((v) => v);

  Future<void> _requestPermissions() async {
    final results = await RtcPermissions.requestAll(_capabilities);
    if (!mounted) return;
    setState(() {
      for (final result in results) {
        _permissions[result.capability] = result.granted;
      }
    });
  }

  Future<void> _startForegroundService() async {
    try {
      await RtcLinkPlatform.instance.startForegroundService(
        title: 'RTC Link publishing',
        text: 'Audio/video publishing is active',
      );
    } on RtcException catch (e) {
      _showSnack(e.message);
    }
  }

  Future<void> _stopForegroundService() async {
    await RtcLinkPlatform.instance.stopForegroundService();
  }

  Future<void> _runDiagnostics() async {
    final report = await Diagnostics.run(
      networkProbe: NetworkProbe(
        targets: const <NetworkProbeTarget>[
          NetworkProbeTarget(host: 'turn.example.com', port: 3478),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _report = report.toMarkdown());
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
