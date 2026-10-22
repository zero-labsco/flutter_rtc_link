import 'dart:async';

import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake teleop channel for watchdog and command tests. / 用于看门狗与指令测试的假通道。
class FakeTeleopChannel implements TeleopChannel {
  final List<Velocity> velocities = <Velocity>[];
  final List<PtzCommand> ptzCommands = <PtzCommand>[];
  int stopCount = 0;
  bool connected = false;
  bool nextSendSucceeds = true;

  final StreamController<RobotTelemetry> telemetryCtrl =
      StreamController<RobotTelemetry>.broadcast();

  @override
  bool get isConnected => connected;

  @override
  Stream<RobotTelemetry> get telemetry => telemetryCtrl.stream;

  @override
  Future<void> connect(String deviceId) async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<bool> sendVelocity(Velocity velocity) async {
    velocities.add(velocity);
    return nextSendSucceeds;
  }

  @override
  Future<bool> sendPtz(PtzCommand command) async {
    ptzCommands.add(command);
    return nextSendSucceeds;
  }

  @override
  Future<bool> sendStop() async {
    stopCount++;
    return nextSendSucceeds;
  }
}

void main() {
  group('velocityFromJoystick', () {
    test('up is forward and right is left-turn positive', () {
      final v = velocityFromJoystick(
        dx: 0.5,
        dy: -1,
        maxLinear: 1.0,
        maxAngular: 1.5,
      );
      expect(v.linear, 1.0);
      expect(v.angular, 0.75);
    });

    test('clamps out-of-range offsets', () {
      final v = velocityFromJoystick(
        dx: 2,
        dy: 2,
        maxLinear: 1.0,
        maxAngular: 1.5,
      );
      expect(v.linear, -1.0);
      expect(v.angular, 1.5);
    });
  });

  group('RobotController', () {
    late FakeTeleopChannel channel;
    late RobotController robot;

    setUp(() {
      channel = FakeTeleopChannel();
      robot = RobotController(
        channel: channel,
        watchdogTimeout: const Duration(milliseconds: 60),
        commandInterval: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      await robot.dispose();
      await channel.telemetryCtrl.close();
    });

    test('move clamps, sends and arms the watchdog', () async {
      await robot.move(const Velocity(linear: 99, angular: 99));
      expect(channel.velocities.single.linear, 1.0);
      expect(channel.velocities.single.angular, 1.5);
      expect(robot.currentVelocity.linear, 1.0);
      expect(robot.isWatchdogArmed, isTrue);
    });

    test('keepalive keeps commanding while the link is healthy', () async {
      await robot.connect(deviceId: 'robot-42');
      await robot.move(const Velocity(linear: 0.5));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // The joystick is still held: commands keep flowing, no stop.
      // 摇杆仍被按住：指令持续下发，不停车。
      expect(channel.velocities.length, greaterThan(1));
      expect(channel.stopCount, 0);
      expect(robot.hasWatchdogTripped, isFalse);
    });

    test('a refused command trips the watchdog immediately', () async {
      await robot.connect(deviceId: 'robot-42');
      channel.nextSendSucceeds = false;
      final events = <DeviceEvent>[];
      robot.events.listen(events.add);
      await robot.move(const Velocity(linear: 0.5));
      // Broadcast events are delivered asynchronously. / 广播事件异步投递。
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(channel.stopCount, greaterThanOrEqualTo(1));
      expect(robot.currentVelocity.isZero, isTrue);
      expect(robot.hasWatchdogTripped, isTrue);
      expect(events.whereType<RobotWatchdogTriggered>(), isNotEmpty);
    });

    test('stop disarms the watchdog and sends stop', () async {
      await robot.move(const Velocity(linear: 0.5));
      await robot.stop();
      expect(channel.stopCount, 1);
      expect(robot.isWatchdogArmed, isFalse);
    });

    test('link loss is treated like a command timeout', () async {
      await robot.connect(deviceId: 'robot-42');
      await robot.move(const Velocity(linear: 0.5));
      channel.connected = false;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(channel.stopCount, greaterThanOrEqualTo(1));
      expect(robot.hasWatchdogTripped, isTrue);
    });

    test('setPtz forwards the command', () async {
      await robot.setPtz(pan: 30, tilt: -10, zoom: 2);
      expect(channel.ptzCommands.single.pan, 30);
      expect(channel.ptzCommands.single.tilt, -10);
      expect(channel.ptzCommands.single.zoom, 2);
    });
  });
}
