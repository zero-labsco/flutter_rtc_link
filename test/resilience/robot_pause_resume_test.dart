import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';
import '../robot/robot_controller_test.dart' show FakeTeleopChannel;

void main() {
  group('RobotController pause/resume', () {
    test('pausing stops the robot and invalidates commands', () async {
      // 暂停会停车并使指令失效。
      final channel = FakeTeleopChannel()..connected = true;
      final robot = RobotController(
        channel: channel,
        gate: PauseResumeGate(),
        commandInterval: const Duration(milliseconds: 20),
      );
      addTearDown(robot.dispose);
      await robot.connect(deviceId: 'robot-1');

      final events = <DeviceEvent>[];
      final sub = robot.events.listen(events.add);
      await robot.move(const Velocity(linear: 0.5));
      expect(channel.velocities.length, 1);

      await robot.pause(PauseReason.background);
      expect(channel.stopCount, 1);
      expect(robot.isPaused, isTrue);
      expect(robot.currentVelocity.isZero, isTrue);
      expect(robot.isWatchdogArmed, isFalse);

      // A command issued while paused is dropped, never buffered.
      // 暂停期间下达的指令被丢弃，绝不缓存。
      await robot.move(const Velocity(linear: 0.9));
      expect(channel.velocities.length, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(events.whereType<RobotControlPaused>(), isNotEmpty);
      await sub.cancel();
    });

    test(
      'resume requires a confirmed ticket and drops stale commands',
      () async {
        // 恢复需要已确认的票据，并丢弃过期指令。
        final channel = FakeTeleopChannel()..connected = true;
        final gate = PauseResumeGate();
        final robot = RobotController(channel: channel, gate: gate);
        addTearDown(robot.dispose);
        await robot.connect(deviceId: 'robot-1');

        await robot.pause(PauseReason.connectionLost);
        final ticket = robot.requestResume();
        expect(ticket, isNotNull);
        // Not confirmed yet: commands stay rejected. / 尚未确认：指令仍被拒绝。
        await robot.move(const Velocity(linear: 0.5));
        expect(channel.velocities, isEmpty);

        final resumed = await robot.confirmResume(ticket!);
        expect(resumed, isTrue);
        expect(robot.isPaused, isFalse);

        await robot.move(const Velocity(linear: 0.4));
        expect(channel.velocities.length, 1);
        expect(channel.velocities.single.linear, 0.4);
      },
    );

    test('a foreign ticket cannot resume the robot', () async {
      // 外来票据无法恢复机器人。
      final channel = FakeTeleopChannel()..connected = true;
      final robot = RobotController(channel: channel, gate: PauseResumeGate());
      addTearDown(robot.dispose);
      await robot.connect(deviceId: 'robot-1');
      await robot.pause(PauseReason.user);
      final foreign = ResumeTicket(
        epoch: 42,
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );
      expect(await robot.confirmResume(foreign), isFalse);
      expect(robot.isPaused, isTrue);
      expect(channel.velocities, isEmpty);
    });

    test('the keepalive loop does not replay a pre-pause velocity', () async {
      // 保活循环不会补发暂停前的速度。
      final channel = FakeTeleopChannel()..connected = true;
      final robot = RobotController(
        channel: channel,
        gate: PauseResumeGate(),
        commandInterval: const Duration(milliseconds: 10),
        watchdogTimeout: const Duration(seconds: 5),
      );
      addTearDown(robot.dispose);
      await robot.connect(deviceId: 'robot-1');
      await robot.move(const Velocity(linear: 0.6));
      final afterMove = channel.velocities.length;

      await robot.pause(PauseReason.background);
      await robot.confirmResume(robot.requestResume()!);
      // Give the keepalive loop time to run twice. / 给保活循环跑两次的时间。
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(channel.velocities.length, afterMove);
    });

    test('a controller without a gate keeps its legacy behaviour', () async {
      // 未配置门的控制器沿用旧行为。
      final channel = FakeTeleopChannel()..connected = true;
      final robot = RobotController(channel: channel);
      addTearDown(robot.dispose);
      await robot.connect(deviceId: 'robot-1');
      await robot.move(const Velocity(linear: 0.5));
      expect(channel.velocities.length, 1);
      expect(robot.isPaused, isFalse);
      await robot.pause(PauseReason.user);
      // No gate: pause still stops the robot (safety), but nothing is gated.
      // 没有门：暂停依然会停车（安全），但不做任何管控。
      expect(channel.stopCount, 1);
      await robot.move(const Velocity(linear: 0.5));
      expect(channel.velocities.length, 2);
    });
  });
}
