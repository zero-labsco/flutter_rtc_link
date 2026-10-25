import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';

import 'gatt_inspector.dart';
import 'widgets/instrument.dart';

/// BLE control demo: scan → connect over GATT → joystick teleoperation.
/// BLE 控制演示：扫描 → 经 GATT 连接 → 摇杆远控。
///
/// Shows [BleTeleopChannel] wired into the same [RobotController] the network
/// demo uses, so the watchdog, epoch gating and keepalive behaviour is
/// identical — only the transport changes. / 把 [BleTeleopChannel] 接到与网络
/// 演示相同的 [RobotController]，看门狗、epoch 门控与保活行为完全一致——只是
/// 传输换成了 BLE。
class BleControlDemoPage extends StatefulWidget {
  const BleControlDemoPage({super.key});

  @override
  State<BleControlDemoPage> createState() => _BleControlDemoPageState();
}

class _BleControlDemoPageState extends State<BleControlDemoPage> {
  final _discoverer = BleTeleopDiscoverer();
  List<BleDevice> _devices = const <BleDevice>[];
  BleDevice? _selected;
  BleTeleopChannel? _channel;
  RobotController? _robot;
  RobotTelemetry _telemetry = const RobotTelemetry();
  StreamSubscription<RobotTelemetry>? _telemetrySub;
  StreamSubscription<DeviceEvent>? _eventSub;
  bool _watchdogTripped = false;
  bool _scanning = false;
  bool _scanAll = false;
  String? _error;

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _eventSub?.cancel();
    _robot?.dispose();
    _channel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final robot = _robot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: <Widget>[
        const SectionLabel('scan'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  InstrumentButton(
                    label: _scanning ? 'scanning…' : 'scan ble',
                    icon: Icons.bluetooth_searching,
                    onPressed: _scanning ? null : _scan,
                  ),
                  if (robot != null)
                    InstrumentButton(
                      label: 'disconnect',
                      icon: Icons.link_off,
                      onPressed: _disconnect,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('Teleop'),
                      selected: !_scanAll,
                      onSelected: (_) => setState(() => _scanAll = false),
                    ),
                    ChoiceChip(
                      label: const Text('All devices'),
                      selected: _scanAll,
                      onSelected: (_) => setState(() => _scanAll = true),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: status.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              for (final device in _devices) _deviceRow(device, status),
            ],
          ),
        ),
        if (robot != null) ...<Widget>[
          const SectionLabel('drive'),
          Panel(
            trailing: StatusChip(
              label: _watchdogTripped ? 'watchdog' : 'armed',
              color: _watchdogTripped ? status.error : status.ok,
              active: !_watchdogTripped,
            ),
            child: Joystick(
              size: 180,
              onChanged: _onJoystick,
              onRelease: () => robot.stop(),
            ),
          ),
          const SectionLabel('telemetry'),
          Row(
            children: <Widget>[
              Expanded(
                child: MetricTile(
                  label: 'battery',
                  value: '${_telemetry.battery.toStringAsFixed(0)} %',
                  accent: _batteryAccent(status),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  label: 'linear',
                  value: '${_telemetry.linearSpeed.toStringAsFixed(2)} m/s',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  label: 'angular',
                  value: '${_telemetry.angularSpeed.toStringAsFixed(2)} rad/s',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  label: 'link',
                  value: _telemetry.online ? 'online' : 'offline',
                  accent: _telemetry.online ? status.ok : status.idle,
                ),
              ),
            ],
          ),
        ],
        const SectionLabel('safety'),
        Panel(
          child: Text(
            'Same watchdog as the network demo stops the robot within '
            '${robot?.watchdogTimeout.inMilliseconds ?? 500} ms of the last '
            'command. BLE auto-reconnects on a drop, but link loss still trips '
            'the watchdog if it lasts too long.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceRow(BleDevice device, AppStatusColors status) {
    final selected = device.id == _selected?.id;
    return GestureDetector(
      onTap: () => _onDeviceTap(device),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? status.ok.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? status.ok
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    device.label,
                    style: Theme.of(context).textTheme.monoValue,
                  ),
                  Text(
                    '${device.id} · ${device.rssi} dBm',
                    style: Theme.of(context).textTheme.monoLabel,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  Color _batteryAccent(AppStatusColors status) {
    final battery = _telemetry.battery;
    if (battery <= 15) return status.error;
    if (battery <= 35) return status.warn;
    return status.ok;
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      // Android 12+ requires BLUETOOTH_SCAN / BLUETOOTH_CONNECT; iOS needs the
      // Bluetooth usage description. Request before scanning so it does not fail
      // with a permission error. / Android 12+ 需要蓝牙扫描 / 连接权限，iOS 需要
      // 蓝牙使用说明；扫描前先申请，避免直接抛权限错误。
      final permissions = <RtcPermission>[
        RtcPermission.bluetoothScan,
        RtcPermission.bluetoothConnect,
      ];
      // Unfiltered ("All devices") scans need location on Android 10/11 to
      // return results. / "全部设备"无过滤扫描在 Android 10/11 上需要定位权限
      // 才会返回结果。
      if (_scanAll) {
        permissions.add(RtcPermission.locationWhenInUse);
      }
      final results = await RtcPermissions.requestAll(permissions);
      final denied = results.where((r) => !r.granted).toList();
      if (denied.isNotEmpty) {
        if (!mounted) return;
        setState(
          () => _error =
              'Bluetooth permission denied: ${denied.map((d) => d.capability.name).join(', ')}',
        );
        return;
      }
      if (!await _ensureBluetoothOn()) {
        if (!mounted) return;
        setState(() => _error = 'Bluetooth is off.');
        return;
      }
      // Teleop mode filters to the robot service; "All devices" lists everything
      // via the protocol-agnostic [BleScanner]. / Teleop 模式按机器人服务过滤；
      // "All devices"通过协议无关的 [BleScanner] 列出全部设备。
      final devices = _scanAll
          ? await BleScanner().scan()
          : await _discoverer.scan();
      if (!mounted) return;
      setState(() => _devices = devices);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _onJoystick(double dx, double dy) {
    final robot = _robot;
    if (robot == null) return;
    robot.move(
      velocityFromJoystick(dx: dx, dy: dy, maxLinear: 1.0, maxAngular: 1.5),
    );
  }

  /// Apple-style confirmation before connecting: tap a device, then a
  /// [CupertinoAlertDialog] asks the operator to confirm. When a device is
  /// already connected the wording becomes a *switch*. / 连接前的苹果风二次
  /// 确认：点设备后弹出 [CupertinoAlertDialog] 让操作员确认；若已连接设备，文案
  /// 变为"切换"。
  Future<void> _confirmConnect(BleDevice device) async {
    setState(() => _selected = device);
    final switching = _robot != null;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          switching ? 'Switch to this device?' : 'Connect to this device?',
        ),
        content: Text(
          '${device.label}\n${device.id}\n${device.rssi} dBm'
          '${switching ? '\n\nCurrent connection will be disconnected.' : ''}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: <CupertinoDialogAction>[
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _connect(device);
    }
  }

  /// Routes a device tap: in "All devices" mode open the generic GATT inspector
  /// (speaker / sensor / any peripheral); in "Teleop" mode run the robot
  /// connect flow. / 设备点击路由：在 "All devices" 模式下打开通用 GATT 检视器
  ///（音响 / 传感器 / 任意外设）；在 "Teleop" 模式下走机器人连接流程。
  Future<void> _onDeviceTap(BleDevice device) async {
    if (_scanAll) {
      await showDialog(
        context: context,
        builder: (_) => GattInspector(device: device),
      );
      return;
    }
    await _confirmConnect(device);
  }

  Future<void> _connect(BleDevice device) async {
    if (!await _ensureBluetoothOn()) {
      if (mounted) setState(() => _error = 'Bluetooth is required to connect.');
      return;
    }
    // Switching devices: tear down the previous connection first so we do not
    // leak the old link / controller. / 切换设备：先断开旧连接，避免旧链路 /
    // 控制器泄漏。
    if (_robot != null) await _disconnect();
    final channel = BleTeleopChannel.forDevice(device);
    final robot = RobotController(channel: channel);
    try {
      await robot.connect(deviceId: device.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Connect failed: $e');
      await channel.dispose();
      return;
    }
    _telemetrySub = robot.telemetry.listen((t) {
      if (!mounted) return;
      setState(() => _telemetry = t);
    });
    _eventSub = robot.events.listen((event) {
      if (event is RobotWatchdogTriggered && mounted) {
        setState(() => _watchdogTripped = true);
      }
    });
    setState(() {
      _channel = channel;
      _robot = robot;
    });
  }

  Future<void> _disconnect() async {
    await _robot?.disconnect();
    await _channel?.dispose();
    if (!mounted) return;
    setState(() {
      _robot = null;
      _channel = null;
      _watchdogTripped = false;
      _telemetry = const RobotTelemetry();
    });
  }

  /// Ensures Bluetooth is powered on; if not, shows an Apple-style dialog and
  /// (where supported) attempts to turn it on. Returns false if the operator
  /// cancels or Bluetooth stays off. / 确保蓝牙已开启；若未开启则弹出苹果风
  /// 对话框，并在支持的平台尝试开启。操作员取消或仍关闭时返回 false。
  Future<bool> _ensureBluetoothOn() async {
    BluetoothAdapterState state;
    try {
      state = await FlutterBluePlus.adapterState.first;
    } catch (_) {
      return false;
    }
    if (state == BluetoothAdapterState.on) return true;
    if (!mounted) return false;
    final proceed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Bluetooth is off'),
        content: const Text(
          'This feature needs Bluetooth. Turn it on to continue.',
        ),
        actions: <CupertinoDialogAction>[
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (proceed != true) return false;
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      // iOS / unsupported platforms cannot enable Bluetooth programmatically.
      // iOS / 不支持的平台无法以编程方式开启蓝牙。
    }
    try {
      return await FlutterBluePlus.adapterState.first ==
          BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }
}
