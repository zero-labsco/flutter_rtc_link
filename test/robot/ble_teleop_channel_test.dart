import 'dart:async';

import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [BleLink] so the channel logic is testable without a real device.
/// 内存版 [BleLink]，无需真实设备即可测试通道逻辑。
class FakeBleLink implements BleLink {
  FakeBleLink({this.connected = false});

  final List<Map<String, dynamic>> written = <Map<String, dynamic>>[];
  bool connected;
  final StreamController<Map<String, dynamic>> _telemetryCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _stateCtrl = StreamController<bool>.broadcast();

  void pushTelemetry(Map<String, dynamic> map) => _telemetryCtrl.add(map);

  void goOffline() {
    connected = false;
    _stateCtrl.add(false);
  }

  @override
  Future<void> connect() async {
    connected = true;
    _stateCtrl.add(true);
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    _stateCtrl.add(false);
  }

  @override
  Future<bool> writeCommand(Map<String, dynamic> payload) async {
    if (!connected) return false;
    written.add(payload);
    return true;
  }

  @override
  Stream<Map<String, dynamic>> get telemetry => _telemetryCtrl.stream;

  @override
  Stream<bool> get connectionState => _stateCtrl.stream;

  @override
  bool get isConnected => connected;
}

void main() {
  group('BleTeleopChannel', () {
    late FakeBleLink link;
    late BleTeleopChannel channel;
    late List<RobotTelemetry> telemetry;
    late StreamSubscription<RobotTelemetry> sub;

    setUp(() {
      link = FakeBleLink();
      channel = BleTeleopChannel(link: link);
      telemetry = <RobotTelemetry>[];
      sub = channel.telemetry.listen(telemetry.add);
    });

    tearDown(() async {
      await sub.cancel();
      await channel.dispose();
    });

    test('forwards velocity / ptz / stop envelopes', () async {
      await channel.connect('robot-1');
      expect(channel.isConnected, isTrue);

      await channel.sendVelocity(const Velocity(linear: 0.5, angular: 1.0));
      await channel.sendPtz(const PtzCommand(pan: 10, tilt: -5, zoom: 2));
      await channel.sendStop();

      expect(link.written, hasLength(3));
      expect(link.written[0], <String, dynamic>{
        'type': 'velocity',
        'linear': 0.5,
        'angular': 1.0,
      });
      expect(link.written[1], <String, dynamic>{
        'type': 'ptz',
        'pan': 10,
        'tilt': -5,
        'zoom': 2,
      });
      expect(link.written[2], <String, dynamic>{'type': 'stop'});
    });

    test('parses device telemetry into RobotTelemetry', () async {
      await channel.connect('robot-1');
      link.pushTelemetry(<String, dynamic>{
        'battery': 82,
        'linearSpeed': 0.3,
        'angularSpeed': -0.2,
        'online': true,
      });
      await Future<void>.delayed(Duration.zero);

      final last = telemetry.last;
      expect(last.battery, 82);
      expect(last.linearSpeed, 0.3);
      expect(last.angularSpeed, -0.2);
      expect(last.online, isTrue);
    });

    test('emits an offline frame when the link drops', () async {
      await channel.connect('robot-1');
      link.goOffline();
      await Future<void>.delayed(Duration.zero);

      expect(telemetry.any((t) => !t.online), isTrue);
    });

    test('refuses to write before connect', () async {
      final sent = await channel.sendVelocity(const Velocity());
      expect(sent, isFalse);
    });
  });
}
