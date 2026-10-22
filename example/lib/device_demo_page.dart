import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';

import 'widgets/instrument.dart';

/// Device management demo: BLE scan, provisioning, OTA, logs.
/// 设备管理演示：BLE 扫描、配网、OTA、日志。
class DeviceDemoPage extends StatefulWidget {
  const DeviceDemoPage({super.key});

  @override
  State<DeviceDemoPage> createState() => _DeviceDemoPageState();
}

class _DeviceDemoPageState extends State<DeviceDemoPage> {
  final _ssidCtrl = TextEditingController(text: 'plant-5g');
  final _passwordCtrl = TextEditingController();
  final _dppCtrl = TextEditingController(text: 'DPP:C:1/2;I:test-device');
  final _otaUrlCtrl = TextEditingController(
    text: 'https://cdn.example.com/fw/v2.3.1.bin',
  );
  final _otaShaCtrl = TextEditingController();

  late final DeviceProvisioning _provisioning = DeviceProvisioning(
    ble: EspBleProvisioningChannel(),
    dpp: const DppProvisioningChannelImpl(),
    nfc: const NfcProvisioningChannelImpl(),
    softAp: const WifiIotSoftApChannel(),
  );

  List<ProvisionDevice> _devices = const <ProvisionDevice>[];
  ProvisioningStatus _status = const ProvisioningStatus();
  OtaProgress? _otaProgress;
  DeviceLogCollector? _logger;
  StreamSubscription<ProvisioningStatus>? _statusSub;
  StreamSubscription<DeviceEvent>? _logEventSub;
  final List<DeviceLogEntry> _logPreview = <DeviceLogEntry>[];

  @override
  void dispose() {
    _statusSub?.cancel();
    _logEventSub?.cancel();
    _provisioning.dispose();
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    _dppCtrl.dispose();
    _otaUrlCtrl.dispose();
    _otaShaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: <Widget>[
        const SectionLabel('wifi credentials'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FieldRow(label: 'ssid', controller: _ssidCtrl),
              FieldRow(
                label: 'password',
                controller: _passwordCtrl,
                obscureText: true,
              ),
            ],
          ),
        ),
        const SectionLabel('provisioning'),
        Panel(
          trailing: _provisioningChip(status),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Wrap instead of a fixed three-up Row so the SCAN BLE / DPP / NFC
              // actions flow to the next line on narrow screens instead of
              // overflowing. / 用 Wrap 替代固定三列 Row，窄屏时自动换行避免溢出。
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  InstrumentButton(
                    label: 'scan ble',
                    icon: Icons.bluetooth_searching,
                    onPressed: _scanBle,
                  ),
                  InstrumentButton(
                    label: 'dpp',
                    icon: Icons.qr_code_scanner,
                    onPressed: _provisionViaDpp,
                  ),
                  InstrumentButton(
                    label: 'nfc',
                    icon: Icons.nfc,
                    onPressed: _readNfcTag,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FieldRow(label: 'dpp qr content', controller: _dppCtrl),
              if (_status.reason != ProvisionFailureReason.none)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_status.reason.name} · ${_status.message ?? ''}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: status.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              for (final device in _devices)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              device.name.isEmpty ? device.id : device.name,
                              style: Theme.of(context).textTheme.monoValue,
                            ),
                            Text(
                              device.id,
                              style: Theme.of(context).textTheme.monoLabel,
                            ),
                          ],
                        ),
                      ),
                      InstrumentButton(
                        label: 'provision',
                        onPressed: () => _provisionBle(device),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SectionLabel('firmware'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FieldRow(label: 'firmware url', controller: _otaUrlCtrl),
              FieldRow(label: 'expected sha-256', controller: _otaShaCtrl),
              InstrumentButton(
                label: 'start ota',
                icon: Icons.system_update,
                primary: _otaProgress == null,
                onPressed: _runOta,
              ),
              if (_otaProgress != null) ...<Widget>[
                const SizedBox(height: 12),
                ReadoutRow(
                  label: 'stage',
                  value: _otaProgress!.stage.name,
                  color: _otaProgress!.stage == OtaStage.failed
                      ? status.error
                      : null,
                ),
                ReadoutRow(
                  label: 'percent',
                  value: '${_otaProgress!.percent.toStringAsFixed(0)} %',
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (_otaProgress!.percent / 100).clamp(0.0, 1.0),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SectionLabel('logs'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: InstrumentButton(
                      label: 'collect',
                      icon: Icons.article,
                      onPressed: _startLogging,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InstrumentButton(
                      label: 'flush',
                      icon: Icons.cloud_upload,
                      onPressed: _flushLogs,
                    ),
                  ),
                ],
              ),
              for (final entry in _logPreview.reversed.take(8))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${entry.level.name.toUpperCase()} ${entry.tag} · ${entry.message}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: entry.level == LogLevel.error
                          ? status.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _provisioningChip(AppStatusColors status) {
    final state = _status.state;
    final color = switch (state) {
      ProvisioningState.success => status.ok,
      ProvisioningState.failed => status.error,
      ProvisioningState.scanning ||
      ProvisioningState.connecting ||
      ProvisioningState.sendingCredentials ||
      ProvisioningState.verifying => status.warn,
      ProvisioningState.idle => status.idle,
    };
    return StatusChip(
      label: state.name,
      color: color,
      active: color == status.warn,
    );
  }

  WifiCredential get _wifi =>
      WifiCredential(ssid: _ssidCtrl.text, password: _passwordCtrl.text);

  Future<void> _scanBle() async {
    _statusSub ??= _provisioning.status.listen((s) {
      if (!mounted) return;
      setState(() => _status = s);
    });
    final devices = await _provisioning.scanBle();
    if (!mounted) return;
    setState(() => _devices = devices);
  }

  Future<void> _provisionBle(ProvisionDevice device) async {
    await _provisioning.provision(device, wifi: _wifi);
  }

  Future<void> _provisionViaDpp() async {
    await _provisioning.provisionViaDpp(qrContent: _dppCtrl.text);
  }

  Future<void> _readNfcTag() async {
    await _provisioning.provisionViaNfc();
  }

  Future<void> _runOta() async {
    final ota = OtaUpdater(channel: OtaChannel.http);
    await for (final progress in ota.upgrade(
      deviceId: 'robot-42',
      firmwareUrl: _otaUrlCtrl.text,
      expectedSha256: _otaShaCtrl.text.isEmpty ? null : _otaShaCtrl.text,
    )) {
      if (!mounted) return;
      setState(() => _otaProgress = progress);
      if (progress.stage == OtaStage.done ||
          progress.stage == OtaStage.failed) {
        break;
      }
    }
  }

  Future<void> _startLogging() async {
    final logger = DeviceLogCollector(deviceId: 'robot-42', maxBatchSize: 20);
    _logEventSub ??= logger.events.listen((event) {
      if (event is LogBatchUploaded && mounted) {
        setState(
          () => _logPreview.add(
            DeviceLogEntry(
              timestamp: DateTime.now(),
              level: LogLevel.info,
              tag: 'uploader',
              message: 'uploaded ${event.count} entries',
            ),
          ),
        );
      }
    });
    await logger.start(deviceId: 'robot-42');
    for (var i = 0; i < 3; i++) {
      logger.log(LogLevel.info, 'demo', 'sample log #$i');
      _logPreview.add(
        DeviceLogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          tag: 'demo',
          message: 'sample log #$i',
        ),
      );
    }
    if (!mounted) return;
    setState(() => _logger = logger);
  }

  Future<void> _flushLogs() async {
    await _logger?.flush();
  }
}
