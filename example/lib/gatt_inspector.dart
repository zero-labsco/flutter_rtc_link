import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/flutter_rtc_link_device.dart';

/// Inspector dialog that connects to any BLE device via [BleGattClient] and
/// shows its GATT services / characteristics. / 检视对话框：经 [BleGattClient]
/// 连接任意 BLE 设备并展示其 GATT 服务 / 特征。
///
/// Demonstrates the protocol-agnostic BLE API on a speaker / sensor / peripheral
/// (anything that is not the robot teleop service). Tap a readable characteristic
/// to read its current value. / 演示协议无关的通用 BLE API 在音响 / 传感器 /
/// 外设（任何非机器人遥测服务的设备）上的用法；点击可读取的特征可读取其当前值。
class GattInspector extends StatefulWidget {
  const GattInspector({super.key, required this.device});

  final BleDevice device;

  @override
  State<GattInspector> createState() => _GattInspectorState();
}

class _GattInspectorState extends State<GattInspector> {
  late final BleGattClient _client;
  late final Future<List<BleGattService>> _discovery;
  final Map<String, String> _readResults = <String, String>{};

  @override
  void initState() {
    super.initState();
    _client = BleGattClient(widget.device);
    _discovery = _client.connect().then((_) => _client.discoverServices());
  }

  @override
  void dispose() {
    // Release the connection and every stream (disconnect alone leaves the
    // connection-state controller open). / 释放连接与全部流（仅 disconnect 会
    // 留下连接状态控制器未关闭）。
    unawaited(_client.dispose());
    super.dispose();
  }

  String _asText(List<int> bytes) {
    try {
      final text = String.fromCharCodes(bytes);
      final isPrintable = text.codeUnits.every(
        (c) => (c >= 32 && c < 127) || c == 10 || c == 13,
      );
      if (isPrintable) return text;
    } catch (_) {
      // Fall through to hex. / 退回到十六进制。
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  Future<void> _read(BleGattCharacteristic c) async {
    try {
      final value = await _client.read(c.uuid);
      if (!mounted) return;
      setState(() => _readResults[c.uuid] = _asText(value));
    } catch (e) {
      if (!mounted) return;
      setState(() => _readResults[c.uuid] = 'read failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.device.label),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<List<BleGattService>>(
          future: _discovery,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text('Connect failed: ${snap.error}');
            }
            final services = snap.data!;
            if (services.isEmpty) {
              return const Text('No GATT services found.');
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: services.length,
              itemBuilder: (ctx, i) {
                final service = services[i];
                return ExpansionTile(
                  title: Text('Service ${service.uuid}'),
                  children: service.characteristics.map((c) {
                    final result = _readResults[c.uuid];
                    return ListTile(
                      title: Text(c.uuid),
                      subtitle: Text(
                        <String>[
                          _propertyText(c),
                          if (result != null) '→ $result',
                        ].join('\n'),
                      ),
                      trailing: c.canRead
                          ? TextButton(
                              onPressed: () => _read(c),
                              child: const Text('Read'),
                            )
                          : null,
                      onTap: c.canRead ? () => _read(c) : null,
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _propertyText(BleGattCharacteristic c) {
    final flags = <String>[
      if (c.canRead) 'read',
      if (c.canWrite) 'write',
      if (c.canWriteWithoutResponse) 'write-no-rsp',
      if (c.canNotify) 'notify',
      if (c.canIndicate) 'indicate',
    ];
    return flags.join(', ');
  }
}
