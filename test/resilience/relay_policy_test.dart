import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stun = IceServer(urls: 'stun:stun.example.com:3478');
  const turnEu = IceServer(
    urls: 'turn:turn-eu.example.com:3478',
    username: 'u',
    credential: 'c',
  );
  const turnAp = IceServer(
    urls: 'turns:turn-ap.example.com:5349?transport=tcp',
    username: 'u',
    credential: 'c',
  );

  group('RelayPlanner', () {
    test('detects TURN capability', () {
      // 检测 TURN 能力。
      expect(const RelayPlanner(servers: <IceServer>[stun]).hasTurn, isFalse);
      expect(
        const RelayPlanner(servers: <IceServer>[stun, turnEu]).hasTurn,
        isTrue,
      );
    });

    test('orders the nearest region first for auto', () {
      // auto 模式下把最近区域排在前面。
      final planner = const RelayPlanner(
        servers: <IceServer>[stun, turnEu, turnAp],
        preferredRegions: <String>['ap'],
      ).orderFor(RelayMode.auto);
      expect(planner.first.urls, turnAp.urls);
      expect(planner.last.urls, stun.urls);
    });

    test('forced relay emits TURN servers and the relay policy', () {
      // 强制中继只输出 TURN，并带上 relay 策略。
      final config = const RelayPlanner(
        servers: <IceServer>[stun, turnEu, turnAp],
      ).configurationFor(RelayMode.forced);
      expect(config['iceTransportPolicy'], 'relay');
      final servers = config['iceServers'] as List<dynamic>;
      expect(servers.length, 2);
    });

    test('direct mode keeps STUN ahead of TURN', () {
      // 直连模式下 STUN 排在 TURN 之前。
      final ordered = const RelayPlanner(servers: <IceServer>[turnEu, stun])
          .orderFor(RelayMode.direct);
      expect(ordered.first.urls, stun.urls);
      expect(ordered.last.urls, turnEu.urls);
    });
  });

  group('relayModeForAttempt', () {
    test('escalates after the configured attempt', () {
      // 在配置的尝试次数之后升级。
      expect(relayModeForAttempt(1, relayAfterAttempts: 2), RelayMode.auto);
      expect(relayModeForAttempt(2, relayAfterAttempts: 2), RelayMode.auto);
      expect(relayModeForAttempt(3, relayAfterAttempts: 2), RelayMode.forced);
    });
  });

  group('IceServer', () {
    test('serializes credentials only when present', () {
      // 仅在存在时才序列化凭证。
      expect(stun.toMap(), <String, dynamic>{'urls': stun.urls});
      expect(turnEu.toMap()['username'], 'u');
    });
  });
}
