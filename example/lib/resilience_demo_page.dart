import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';

import 'widgets/instrument.dart';

/// Resilience lab: the building blocks that keep an overseas, mobile link
/// usable — pause/resume confirmation, network handover, relay escalation and
/// weak-network recovery.
/// 韧性实验室：让海外移动链路保持可用的各个构件——暂停 / 恢复确认、网络切换、
/// 中继升级与弱网恢复。
///
/// Everything here runs locally (no server), so each behaviour can be
/// triggered by hand. / 这里的一切都在本地运行（无需服务器），因此每种行为
/// 都可以手动触发。
class ResilienceDemoPage extends StatefulWidget {
  const ResilienceDemoPage({super.key});

  @override
  State<ResilienceDemoPage> createState() => _ResilienceDemoPageState();
}

class _ResilienceDemoPageState extends State<ResilienceDemoPage> {
  late final PauseResumeGate _gate;
  late final EpochOperationQueue<String> _queue;
  final MediaHealthMonitor _media = MediaHealthMonitor();
  final ReconnectSupervisor _supervisor = ReconnectSupervisor(
    policy: const ReconnectPolicy(jitterRatio: 0),
  );
  final RelayPlanner _relay = const RelayPlanner(
    servers: <IceServer>[
      IceServer(urls: 'stun:stun.example.com:3478'),
      IceServer(
        urls: 'turn:turn-ap.example.com:3478',
        username: '<from-token>',
        credential: '<from-token>',
      ),
    ],
    preferredRegions: <String>['ap'],
  );

  final List<String> _log = <String>[];
  NetworkPath _path = const NetworkPath(kind: NetworkKind.wifi, generation: 1);
  String _handover = 'none';
  bool _iceRestart = false;
  MediaHealth? _mediaHealth;
  String _lastTake = '—';

  @override
  void initState() {
    super.initState();
    _gate = PauseResumeGate(
      confirmationTimeout: const Duration(seconds: 30),
      onEvent: _onGateEvent,
    );
    _queue = EpochOperationQueue<String>(_gate, onDiscard: _onDiscard);
  }

  @override
  void dispose() {
    _media.dispose();
    super.dispose();
  }

  void _onGateEvent(LinkEvent event) {
    setState(() {
      switch (event) {
        case LinkPaused():
          _log.add('paused (${event.reason.name}) → epoch ${event.epoch}');
        case LinkResumeRequested():
          _log.add('resume requested → epoch ${event.ticket.epoch}');
        case LinkResumed():
          _log.add('resumed → epoch ${event.epoch}');
        case LinkResumeRejected():
          _log.add('resume rejected: ${event.reason}');
        case LinkOperationsDiscarded():
          _log.add('dropped ${event.count} op(s): ${event.reason}');
        default:
          break;
      }
    });
  }

  void _onDiscard(String operation, String reason) {
    setState(() => _log.add('discarded "$operation" ($reason)'));
  }

  void _pause() {
    _gate.pause(PauseReason.background);
    setState(() {});
  }

  void _requestResume() {
    _gate.requestResume();
    setState(() {});
  }

  void _confirmResume() {
    final ticket = _gate.pendingTicket;
    if (ticket == null) return;
    final ok = _gate.confirmResume(ticket);
    if (!ok) {
      setState(() => _log.add('confirm rejected (ticket unusable)'));
      return;
    }
    setState(() {});
  }

  void _switchPath(NetworkKind kind, {bool metered = false}) {
    final next = NetworkPath(
      kind: kind,
      metered: metered,
      generation: _path.generation + 1,
    );
    final change = NetworkPathChange(from: _path, to: next);
    setState(() {
      _path = next;
      _handover = change.hasChange
          ? '${change.from.kind.name} → ${change.to.kind.name}'
          : 'none';
      _iceRestart = change.requiresIceRestart();
      _log.add('path $_handover${_iceRestart ? ' (ICE restart)' : ''}');
    });
  }

  void _feedStats(String kind) {
    final now = DateTime.now();
    final stats = RtcStats(
      streamId: 'cam-1',
      kind: RtcTrackKind.video,
      bitrateKbps: kind == 'frozen' ? 20 : 1200,
      packetLossPercent: kind == 'stutter' ? 9 : 1,
      jitterMs: kind == 'stutter' ? 160 : 20,
      rttMs: kind == 'congested' ? 620 : 70,
      fps: kind == 'frozen' ? 0 : 28,
      width: 1280,
      height: 720,
      timestamp: now,
    );
    setState(() {
      _mediaHealth = _media.feed(stats);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ticket = _gate.pendingTicket;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: <Widget>[
        const SectionLabel('pause / resume confirmation'),
        Panel(
          trailing: StatusChip(
            label: _gate.isPaused ? 'paused' : 'active',
            color: _gate.isPaused ? status.warn : status.ok,
            active: !_gate.isPaused,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: MetricTile(label: 'epoch', value: '${_gate.epoch}'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      label: 'dropped ops',
                      value: '${_gate.discardedOperations}',
                      accent: _gate.discardedOperations == 0
                          ? null
                          : status.warn,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  InstrumentButton(
                    label: 'pause',
                    icon: Icons.pause_circle_outline,
                    onPressed: _gate.isPaused ? null : _pause,
                  ),
                  InstrumentButton(
                    label: 'request resume',
                    icon: Icons.play_circle_outline,
                    onPressed: _gate.isPaused ? _requestResume : null,
                  ),
                  InstrumentButton(
                    label: 'confirm',
                    icon: Icons.verified_outlined,
                    primary: true,
                    onPressed: ticket == null ? null : _confirmResume,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ReadoutRow(
                label: 'ticket',
                value: ticket == null
                    ? 'none — resume must be requested first'
                    : 'epoch ${ticket.epoch}, valid ${ticket.remainingAt(DateTime.now()).inSeconds}s',
                color: ticket == null ? status.idle : scheme.primary,
              ),
              ReadoutRow(
                label: 'buffered',
                value: '${_queue.pendingCount} (latest wins)',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  InstrumentButton(
                    label: 'queue command',
                    icon: Icons.add_task,
                    onPressed: () {
                      final accepted = _queue.submit('move(0.6, 0.0)');
                      setState(
                        () => _log.add(
                          accepted
                              ? 'queued under epoch ${_gate.epoch}'
                              : 'queue rejected (paused)',
                        ),
                      );
                    },
                  ),
                  InstrumentButton(
                    label: 'flush queue',
                    icon: Icons.outbox,
                    onPressed: () {
                      final next = _queue.take();
                      setState(() {
                        _lastTake = next ?? 'dropped (stale epoch)';
                        _log.add('flush → $_lastTake');
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ReadoutRow(label: 'last flush', value: _lastTake),
            ],
          ),
        ),
        const SectionLabel('network handover'),
        Panel(
          trailing: StatusChip(
            label: _iceRestart ? 'ice restart' : 'stable',
            color: _iceRestart ? status.warn : status.ok,
            active: _iceRestart,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  InstrumentButton(
                    label: 'wi-fi',
                    icon: Icons.wifi,
                    onPressed: () => _switchPath(NetworkKind.wifi),
                  ),
                  InstrumentButton(
                    label: 'cellular',
                    icon: Icons.signal_cellular_alt,
                    onPressed: () =>
                        _switchPath(NetworkKind.cellular, metered: true),
                  ),
                  InstrumentButton(
                    label: 'offline',
                    icon: Icons.signal_wifi_off,
                    danger: true,
                    onPressed: () => _switchPath(NetworkKind.none),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ReadoutRow(label: 'path', value: _path.toString()),
              ReadoutRow(label: 'change', value: _handover),
              ReadoutRow(
                label: 'relay',
                value:
                    '${_relay.orderFor(RelayMode.forced).length} turn / '
                    '${_relay.orderFor(RelayMode.auto).length} candidates',
              ),
            ],
          ),
        ),
        const SectionLabel('weak network'),
        Panel(
          trailing: StatusChip(
            label: _mediaHealth?.issue.name ?? 'unknown',
            color: _issueColor(status),
            active: _mediaHealth?.isFrozen ?? false,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  InstrumentButton(
                    label: 'healthy',
                    icon: Icons.check_circle_outline,
                    onPressed: () => _feedStats('healthy'),
                  ),
                  InstrumentButton(
                    label: 'stutter',
                    icon: Icons.grain,
                    onPressed: () => _feedStats('stutter'),
                  ),
                  InstrumentButton(
                    label: 'congested',
                    icon: Icons.speed,
                    onPressed: () => _feedStats('congested'),
                  ),
                  InstrumentButton(
                    label: 'frozen',
                    icon: Icons.ac_unit,
                    danger: true,
                    onPressed: () => _feedStats('frozen'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ReadoutRow(
                label: 'action',
                value: _mediaHealth?.action.name ?? 'none',
                color: (_mediaHealth?.needsRecovery ?? false)
                    ? status.warn
                    : null,
              ),
              ReadoutRow(
                label: 'frozen for',
                value:
                    '${_mediaHealth?.frozenFor(DateTime.now()).inSeconds ?? 0} s',
              ),
            ],
          ),
        ),
        const SectionLabel('reconnect backoff'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var attempt = 1; attempt <= 4; attempt++)
                ReadoutRow(
                  label: 'attempt $attempt',
                  value:
                      '${_supervisor.policy.delayForAttempt(attempt).inMilliseconds} ms'
                      ' · ${relayModeForAttempt(attempt, relayAfterAttempts: _supervisor.policy.relayAfterAttempts).name}',
                ),
              const SizedBox(height: 12),
              InstrumentButton(
                label: 'schedule a retry',
                icon: Icons.restart_alt,
                onPressed: () {
                  final delay = _supervisor.scheduleNext();
                  setState(
                    () => _log.add(
                      delay == null
                          ? 'budget exhausted'
                          : 'attempt ${_supervisor.attempt} in ${delay.inMilliseconds} ms'
                                ' (${_supervisor.currentRelayMode.name})',
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SectionLabel('event log'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_log.isEmpty)
                ReadoutRow(label: 'log', value: 'no events yet')
              else
                for (final line in _log.reversed.take(12))
                  ReadoutRow(
                    label: 'evt',
                    value: line,
                    color: scheme.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Color _issueColor(AppStatusColors status) {
    switch (_mediaHealth?.issue) {
      case MediaHealthIssue.frozen:
        return status.error;
      case MediaHealthIssue.congested:
        return status.warn;
      case MediaHealthIssue.stuttering:
        return status.warn;
      case MediaHealthIssue.healthy:
        return status.ok;
      case null:
        return status.idle;
    }
  }
}
