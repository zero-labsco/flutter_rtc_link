import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/rtc_link.dart';

import 'widgets/instrument.dart';

/// Robot demo: joystick teleoperation with watchdog + telemetry.
/// 机器人演示：摇杆远控（带看门狗）+ 遥测。
class RobotDemoPage extends StatefulWidget {
  const RobotDemoPage({super.key});

  @override
  State<RobotDemoPage> createState() => _RobotDemoPageState();
}

class _RobotDemoPageState extends State<RobotDemoPage> {
  final _brokerCtrl = TextEditingController(
    text: 'mqtts://mqtt.example.com:8883',
  );
  final _cmdCtrl = TextEditingController(text: 'robot/42/cmd');
  final _telemetryTopicCtrl = TextEditingController(text: 'robot/42/telemetry');

  RobotController? _robot;
  RobotTelemetry _telemetry = const RobotTelemetry();
  StreamSubscription<RobotTelemetry>? _telemetrySub;
  StreamSubscription<DeviceEvent>? _eventSub;
  bool _watchdogTripped = false;
  double _pan = 0;
  double _tilt = 0;

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _eventSub?.cancel();
    _robot?.dispose();
    _brokerCtrl.dispose();
    _cmdCtrl.dispose();
    _telemetryTopicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final robot = _robot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: <Widget>[
        const SectionLabel('control channel'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FieldRow(label: 'mqtt broker', controller: _brokerCtrl),
              FieldRow(label: 'command topic', controller: _cmdCtrl),
              FieldRow(
                label: 'telemetry topic',
                controller: _telemetryTopicCtrl,
              ),
              InstrumentButton(
                label: robot == null ? 'connect robot' : 'disconnect',
                icon: robot == null ? Icons.link : Icons.link_off,
                primary: robot == null,
                onPressed: robot == null ? _connect : _disconnect,
              ),
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
            child: Column(
              children: <Widget>[
                Joystick(
                  size: 180,
                  onChanged: _onJoystick,
                  onRelease: () => robot.stop(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _axisSlider(
                        label: 'pan',
                        value: _pan,
                        min: -180,
                        max: 180,
                        divisions: 36,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _axisSlider(
                        label: 'tilt',
                        value: _tilt,
                        min: -90,
                        max: 90,
                        divisions: 18,
                      ),
                    ),
                  ],
                ),
              ],
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
            'Watchdog stops the robot within ${robot?.watchdogTimeout.inMilliseconds ?? 500} ms '
            'of the last command — link loss counts as a timeout.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _axisSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$label ${value.toStringAsFixed(0)}°',
          style: Theme.of(context).textTheme.monoLabel,
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (v) => setState(() {
            if (label == 'pan') {
              _pan = v;
            } else {
              _tilt = v;
            }
          }),
          onChangeEnd: (_) => _sendPtz(),
        ),
      ],
    );
  }

  Color _batteryAccent(AppStatusColors status) {
    final battery = _telemetry.battery;
    if (battery <= 15) return status.error;
    if (battery <= 35) return status.warn;
    return status.ok;
  }

  void _onJoystick(double dx, double dy) {
    final robot = _robot;
    if (robot == null) return;
    robot.move(
      velocityFromJoystick(dx: dx, dy: dy, maxLinear: 1.0, maxAngular: 1.5),
    );
  }

  Future<void> _sendPtz() async {
    await _robot?.setPtz(pan: _pan, tilt: _tilt);
  }

  Future<void> _connect() async {
    final robot = RobotController(
      channel: MqttTeleopChannel(
        broker: _brokerCtrl.text,
        topicCmd: _cmdCtrl.text,
        topicTelemetry: _telemetryTopicCtrl.text,
        // Credentials are fetched from your auth service at runtime.
        // 凭证在运行时从你的鉴权服务获取。
        credentials: () async => null,
      ),
    );
    await robot.connect(deviceId: 'robot-42');
    _telemetrySub = robot.telemetry.listen((t) {
      if (!mounted) return;
      setState(() => _telemetry = t);
    });
    _eventSub = robot.events.listen((event) {
      if (event is RobotWatchdogTriggered && mounted) {
        setState(() => _watchdogTripped = true);
      }
    });
    setState(() => _robot = robot);
  }

  Future<void> _disconnect() async {
    await _robot?.disconnect();
    if (!mounted) return;
    setState(() => _robot = null);
  }
}
