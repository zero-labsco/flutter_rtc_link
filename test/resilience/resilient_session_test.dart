import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Lets the event loop and pending timers run. / 让事件循环与待处理定时器运行。
Future<void> _tick([int millis = 20]) =>
    Future<void>.delayed(Duration(milliseconds: millis));

class _FakeSubscriber implements RemoteSubscriber {
  _FakeSubscriber(this.streamId, [ClarityLevel level = ClarityLevel.auto])
    : _clarity = ValueNotifier<ClarityLevel>(level);

  @override
  final String streamId;

  final ValueNotifier<ClarityLevel> _clarity;
  int disposeCount = 0;

  @override
  ValueNotifier<ClarityLevel> get clarity => _clarity;

  @override
  VideoRenderer? get videoRenderer => null;

  @override
  Stream<RtcStats> get stats => const Stream<RtcStats>.empty();

  @override
  Future<void> setClarity(ClarityLevel level) async {
    _clarity.value = level;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _FakeSession implements RtcSession {
  _FakeSession(this.roomId, {RtcRole initialRole = RtcRole.viewer})
    : role = ValueNotifier<RtcRole>(initialRole);

  @override
  final String roomId;

  @override
  final ValueNotifier<RtcRole> role;

  final StreamController<RtcEvent> eventsCtrl =
      StreamController<RtcEvent>.broadcast();
  final StreamController<RtcStats> statsCtrl =
      StreamController<RtcStats>.broadcast();
  final StreamController<List<RemoteStream>> remoteCtrl =
      StreamController<List<RemoteStream>>.broadcast();

  final List<String> subscribed = <String>[];
  final List<String> unsubscribed = <String>[];
  int leaveCount = 0;
  int disposeCount = 0;

  @override
  LocalPublisher? get localPublisher => null;

  @override
  Stream<List<RemoteStream>> get remoteStreams => remoteCtrl.stream;

  @override
  Stream<RtcEvent> get events => eventsCtrl.stream;

  @override
  Stream<RtcStats> get stats => statsCtrl.stream;

  @override
  Future<RemoteSubscriber> subscribe({
    required String streamId,
    VideoQuality quality = VideoQuality.auto,
  }) async {
    subscribed.add(streamId);
    return _FakeSubscriber(streamId, quality);
  }

  @override
  Future<void> unsubscribe(String streamId) async {
    unsubscribed.add(streamId);
  }

  @override
  Future<void> leave() async {
    leaveCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  void emit(RtcEvent event) => eventsCtrl.add(event);
}

class _Harness {
  final List<_FakeSession> created = <_FakeSession>[];
  bool failNext = false;

  _FakeSession get last => created.last;

  Future<RtcSession> factory({
    required String roomId,
    required RtcRole role,
    String? identity,
  }) async {
    if (failNext) {
      throw const RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'signaling down',
      );
    }
    final session = _FakeSession(roomId, initialRole: role);
    created.add(session);
    return session;
  }
}

ResilientSessionConfig _config({
  RelayPlanner? relay,
  NetworkPathMonitor? monitor,
  Future<void> Function(RtcSession, RelayMode)? iceRestarter,
  Future<void> Function(RemoteSubscriber, ClarityLevel)? degrader,
  LinkPolicy? policy,
}) => ResilientSessionConfig(
  policy:
      policy ??
      const LinkPolicy(
        reconnect: ReconnectPolicy(
          baseDelay: Duration(milliseconds: 2),
          maxAttempts: 3,
          jitterRatio: 0,
        ),
        background: BackgroundPolicy(gracePeriod: Duration.zero),
      ),
  relay: relay,
  monitor: monitor,
  iceRestarter: iceRestarter,
  degrader: degrader,
);

void main() {
  group('ResilientSession connect', () {
    test('establishes the session and reports connected', () async {
      // 建立会话并上报已连接。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.iotViewer,
        factory: harness.factory,
        config: _config(),
      );
      addTearDown(session.dispose);
      expect(harness.created.length, 1);
      expect(session.roomId, 'room-1');
      expect(session.health.phase, LinkPhase.connected);
      expect(session.health.isUsable, isTrue);
    });

    test('a failing first connect surfaces the error', () async {
      // 首次连接失败会上抛错误。
      final harness = _Harness()..failNext = true;
      await expectLater(
        ResilientSession.connect(
          roomId: 'room-1',
          role: RtcRole.viewer,
          factory: harness.factory,
          config: _config(),
        ),
        throwsA(isA<RtcException>()),
      );
    });
  });

  group('ResilientSession reconnect', () {
    test('re-subscribes every stream after the link comes back', () async {
      // 链路恢复后重新订阅每一路流。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.iotViewer,
        factory: harness.factory,
        config: _config(),
      );
      addTearDown(session.dispose);
      await session.subscribe(streamId: 'cam-1');
      expect(harness.last.subscribed, <String>['cam-1']);

      harness.last.eventsCtrl.add(const RtcDisconnected(reason: 'server'));
      await _tick(60);

      expect(harness.created.length, 2);
      expect(harness.created.first.leaveCount, 1);
      expect(harness.created.last.subscribed, <String>['cam-1']);
      expect(session.health.phase, LinkPhase.connected);
      expect(session.pendingResumeTicket, isNotNull);
      expect(await session.confirmResume(), isTrue);
      expect(session.gate.isPaused, isFalse);
    });

    test('pauses operations while the link is down', () async {
      // 链路中断期间暂停操作。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(),
      );
      addTearDown(session.dispose);
      harness.failNext = true;
      harness.last.eventsCtrl.add(const RtcDisconnected(reason: 'gone'));
      await _tick(5);
      expect(session.gate.isPaused, isTrue);
      expect(session.health.phase, LinkPhase.reconnecting);
      expect(session.health.attempt, greaterThanOrEqualTo(1));
    });

    test('gives up after the budget is exhausted', () async {
      // 预算耗尽后放弃。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(
          policy: const LinkPolicy(
            reconnect: ReconnectPolicy(
              baseDelay: Duration(milliseconds: 1),
              maxAttempts: 1,
              jitterRatio: 0,
            ),
          ),
        ),
      );
      addTearDown(session.dispose);
      final events = <LinkEvent>[];
      final sub = session.linkEvents.listen(events.add);
      harness.failNext = true;
      harness.last.eventsCtrl.add(const RtcDisconnected(reason: 'gone'));
      await _tick(60);
      expect(session.health.phase, LinkPhase.failed);
      expect(
        events.whereType<LinkGaveUp>(),
        isNotEmpty,
        reason: 'a fatal LinkGaveUp must reach the app',
      );
      await sub.cancel();
    });

    test('a restored network path resets the retry budget', () async {
      // 网络路径恢复会重置重试预算。
      final monitor = CallbackNetworkMonitor(
        initial: const NetworkPath(kind: NetworkKind.wifi, generation: 1),
      );
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(monitor: monitor),
      );
      addTearDown(session.dispose);
      // Burn the whole retry budget first. / 先耗尽整个重试预算。
      harness.failNext = true;
      harness.last.eventsCtrl.add(const RtcDisconnected(reason: 'gone'));
      await _tick(60);
      expect(session.health.phase, LinkPhase.failed);

      harness.failNext = false;
      monitor.update(const NetworkPath(kind: NetworkKind.none, generation: 2));
      await _tick(5);
      monitor.update(const NetworkPath(kind: NetworkKind.wifi, generation: 3));
      await _tick(60);
      expect(session.health.phase, LinkPhase.connected);
      expect(session.health.path.generation, 3);
    });
  });

  group('ResilientSession handover', () {
    test(
      'Wi-Fi to cellular restarts ICE and forces relay on cellular',
      () async {
        // Wi-Fi 切蜂窝会重启 ICE，并在蜂窝下强制中继。
        final monitor = CallbackNetworkMonitor(
          initial: const NetworkPath(kind: NetworkKind.wifi, generation: 1),
        );
        final restarts = <RelayMode>[];
        final harness = _Harness();
        final session = await ResilientSession.connect(
          roomId: 'room-1',
          role: RtcRole.viewer,
          factory: harness.factory,
          config: _config(
            monitor: monitor,
            relay: const RelayPlanner(
              servers: <IceServer>[
                IceServer(
                  urls: 'turn:turn-eu.example.com:3478',
                  username: 'u',
                  credential: 'c',
                ),
              ],
            ),
            iceRestarter: (_, mode) async {
              restarts.add(mode);
            },
          ),
        );
        addTearDown(session.dispose);

        monitor.update(
          const NetworkPath(
            kind: NetworkKind.cellular,
            generation: 2,
            metered: true,
          ),
        );
        await _tick(10);
        expect(restarts, <RelayMode>[RelayMode.forced]);
        expect(session.health.path.kind, NetworkKind.cellular);
      },
    );

    test('same-kind roaming does not restart ICE by default', () async {
      // 同类型漫游默认不重启 ICE。
      final monitor = CallbackNetworkMonitor(
        initial: const NetworkPath(kind: NetworkKind.wifi, generation: 1),
      );
      final restarts = <RelayMode>[];
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: _Harness().factory,
        config: _config(
          monitor: monitor,
          iceRestarter: (_, mode) async {
            restarts.add(mode);
          },
        ),
      );
      addTearDown(session.dispose);
      monitor.update(
        const NetworkPath(kind: NetworkKind.wifi, generation: 2, label: 'ap-2'),
      );
      await _tick(10);
      expect(restarts, isEmpty);
    });
  });

  group('ResilientSession background', () {
    test('background pauses and resume needs a confirmation', () async {
      // 后台会暂停，恢复需要确认。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(),
      );
      addTearDown(session.dispose);

      await session.setBackground(true);
      expect(session.isBackgrounded, isTrue);
      expect(session.gate.isPaused, isTrue);
      expect(session.health.paused, isTrue);

      await session.setBackground(false);
      expect(session.pendingResumeTicket, isNotNull);
      // Still paused: the operator must confirm. / 仍处于暂停：需操作者确认。
      expect(session.gate.isPaused, isTrue);

      expect(await session.confirmResume(), isTrue);
      expect(session.gate.isPaused, isFalse);
      expect(session.gate.accepts(session.gate.stamp()), isTrue);
    });

    test('an unknown ticket cannot resume the link', () async {
      // 未知票据无法恢复链路。
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: _Harness().factory,
        config: _config(),
      );
      addTearDown(session.dispose);
      await session.setBackground(true);
      final foreign = ResumeTicket(
        epoch: 99,
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
      );
      expect(await session.confirmResume(foreign), isFalse);
      expect(session.gate.isPaused, isTrue);
    });
  });

  group('ResilientSession weak network', () {
    test('a frozen stream is re-subscribed', () async {
      // 冻结的流会被重新订阅。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(
          policy: const LinkPolicy(
            background: BackgroundPolicy(gracePeriod: Duration.zero),
            weakNetwork: WeakNetworkPolicy(
              frozenSamples: 1,
              keyframeAfter: Duration.zero,
              resubscribeAfter: Duration.zero,
            ),
          ),
        ),
      );
      addTearDown(session.dispose);
      await session.subscribe(streamId: 'cam-1');
      final target = harness.last;

      target.statsCtrl.add(
        RtcStats(
          streamId: 'cam-1',
          kind: RtcTrackKind.video,
          bitrateKbps: 900,
          rttMs: 60,
          fps: 0,
          timestamp: DateTime.now(),
        ),
      );
      await _tick(20);
      expect(target.unsubscribed, <String>['cam-1']);
      expect(target.subscribed.length, 2);
    });

    test('congestion downgrades the clarity', () async {
      // 拥塞会降低清晰度。
      final harness = _Harness();
      final degraded = <ClarityLevel>[];
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(
          policy: const LinkPolicy(
            background: BackgroundPolicy(gracePeriod: Duration.zero),
            weakNetwork: WeakNetworkPolicy(
              frozenSamples: 1,
              degradeAfter: Duration.zero,
            ),
          ),
          degrader: (subscriber, level) async {
            degraded.add(level);
          },
        ),
      );
      addTearDown(session.dispose);
      await session.subscribe(streamId: 'cam-1', quality: ClarityLevel.p720);
      harness.last.statsCtrl.add(
        RtcStats(
          streamId: 'cam-1',
          kind: RtcTrackKind.video,
          bitrateKbps: 900,
          rttMs: 520,
          fps: 24,
          timestamp: DateTime.now(),
        ),
      );
      await _tick(20);
      expect(degraded, <ClarityLevel>[ClarityLevel.p540]);
    });
  });

  group('ResilientSession leave', () {
    test('an explicit leave never reconnects on a later handover', () async {
      // 显式离开之后，后续切换绝不会触发重连。
      final monitor = CallbackNetworkMonitor(
        initial: const NetworkPath(kind: NetworkKind.wifi, generation: 1),
      );
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(monitor: monitor),
      );
      addTearDown(session.dispose);
      await session.leave();
      expect(session.health.phase, LinkPhase.idle);

      monitor.update(
        const NetworkPath(kind: NetworkKind.cellular, generation: 2),
      );
      await _tick(40);
      expect(harness.created.length, 1, reason: 'leave must stop reconnects');
      expect(session.health.phase, LinkPhase.idle);
    });
  });

  group('ResilientSession dispose', () {
    test('a failed first connect releases the monitor', () async {
      // 首次连接失败时也要释放监测器，避免调用方拿不到引用而泄漏。
      final monitor = CallbackNetworkMonitor();
      final harness = _Harness()..failNext = true;
      await expectLater(
        ResilientSession.connect(
          roomId: 'room-1',
          role: RtcRole.viewer,
          factory: harness.factory,
          config: _config(monitor: monitor),
        ),
        throwsA(isA<RtcException>()),
      );
      expect(monitor.isStarted, isFalse);
    });

    test('closes the session and ignores late events', () async {
      // 关闭会话并忽略迟到的事件。
      final harness = _Harness();
      final session = await ResilientSession.connect(
        roomId: 'room-1',
        role: RtcRole.viewer,
        factory: harness.factory,
        config: _config(),
      );
      await session.dispose();
      expect(harness.created.single.leaveCount, 1);
      // Emitting after disposal must not throw. / 释放后发送事件不得抛错。
      session.emit(const RtcDisconnected(reason: 'late'));
      await _tick(5);
    });
  });
}
