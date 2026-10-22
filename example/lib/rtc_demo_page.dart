import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'widgets/instrument.dart';

/// RTC demo: WHIP publish + WHEP subscribe + clarity switching.
/// RTC 演示：WHIP 推流 + WHEP 订阅 + 清晰度切换。
class RtcDemoPage extends StatefulWidget {
  const RtcDemoPage({super.key});

  @override
  State<RtcDemoPage> createState() => _RtcDemoPageState();
}

class _RtcDemoPageState extends State<RtcDemoPage> {
  final _whipCtrl = TextEditingController(
    text: 'http://127.0.0.1:1985/rtc/v1/whip/',
  );
  final _whepCtrl = TextEditingController(
    text: 'http://127.0.0.1:1985/rtc/v1/whep/',
  );
  final _roomCtrl = TextEditingController(text: 'site-42');
  final _streamCtrl = TextEditingController(text: 'cam-01');

  RtcEngine? _engine;
  RtcSession? _session;
  RemoteSubscriber? _subscriber;
  final _previewRenderer = RTCVideoRenderer();
  final List<String> _log = <String>[];
  RtcStats? _latestStats;
  StreamSubscription<RtcEvent>? _eventSub;
  StreamSubscription<RtcStats>? _statsSub;

  @override
  void dispose() {
    _eventSub?.cancel();
    _statsSub?.cancel();
    _previewRenderer.dispose();
    _session?.dispose();
    _engine?.dispose();
    _whipCtrl.dispose();
    _whepCtrl.dispose();
    _roomCtrl.dispose();
    _streamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = AppStatusColors.of(context);
    final session = _session;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: <Widget>[
        const SectionLabel('endpoint'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FieldRow(label: 'whip url', controller: _whipCtrl),
              FieldRow(label: 'whep url', controller: _whepCtrl),
              FieldRow(label: 'room / stream id', controller: _roomCtrl),
              Row(
                children: <Widget>[
                  Expanded(
                    child: InstrumentButton(
                      label: session == null ? 'join anchor' : 'leave',
                      icon: session == null ? Icons.login : Icons.logout,
                      primary: session == null,
                      danger: session != null,
                      onPressed: session == null ? _joinAnchor : _leave,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InstrumentButton(
                      label: 'subscribe',
                      icon: Icons.subscriptions,
                      onPressed: session == null ? null : _subscribe,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FieldRow(label: 'stream id', controller: _streamCtrl),
            ],
          ),
        ),
        if (session != null) ...<Widget>[
          const SectionLabel('local publish'),
          Panel(
            trailing: StatusChip(
              label: 'live',
              color: status.live,
              active: true,
            ),
            child: Column(
              children: <Widget>[
                RtcControlBar(
                  publisher: session.localPublisher!,
                  onLeave: _leave,
                ),
                const SizedBox(height: 12),
                _videoStage(
                  child: RtcVideoView(renderer: _previewRenderer),
                  overlay: 'LOCAL · ${session.roomId}',
                ),
              ],
            ),
          ),
          const SectionLabel('link stats'),
          _statsGrid(),
          if (_subscriber != null) ...<Widget>[
            const SectionLabel('remote stream'),
            Panel(
              child: Column(
                children: <Widget>[
                  _videoStage(
                    child: RtcVideoView(subscriber: _subscriber),
                    overlay: 'REMOTE · ${_subscriber!.streamId}',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final level in const <ClarityLevel>[
                        ClarityLevel.auto,
                        ClarityLevel.p360,
                        ClarityLevel.p540,
                        ClarityLevel.p720,
                        ClarityLevel.p1080,
                      ])
                        ActionChip(
                          label: Text(level.label),
                          onPressed: () => _subscriber!.setClarity(level),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
        const SectionLabel('event log'),
        Panel(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_log.isEmpty)
                Text(
                  'no events yet — join a session first',
                  style: Theme.of(context).textTheme.monoLabel,
                ),
              for (final line in _log.reversed.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _videoStage({required Widget child, required String overlay}) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            child,
            Positioned(left: 8, top: 8, child: _overlayTag(overlay)),
          ],
        ),
      ),
    );
  }

  Widget _overlayTag(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outline),
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.monoLabel,
      ),
    );
  }

  Widget _statsGrid() {
    final stats = _latestStats;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: MetricTile(
            label: 'bitrate',
            value: '${stats?.bitrateKbps.toStringAsFixed(0) ?? '--'} kbps',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MetricTile(
            label: 'rtt',
            value: '${stats?.rttMs.toStringAsFixed(0) ?? '--'} ms',
            accent: _qualityAccent(scheme),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MetricTile(
            label: 'loss',
            value: '${stats?.packetLossPercent.toStringAsFixed(1) ?? '--'} %',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MetricTile(
            label: 'fps',
            value: stats?.fps.toStringAsFixed(0) ?? '--',
          ),
        ),
      ],
    );
  }

  Color _qualityAccent(ColorScheme scheme) {
    if (_latestStats == null) return scheme.onSurfaceVariant;
    final status = AppStatusColors.of(context);
    switch (connectionQualityFrom(_latestStats!)) {
      case ConnectionQualityLevel.poor:
        return status.error;
      case ConnectionQualityLevel.fair:
        return status.warn;
      default:
        return status.ok;
    }
  }

  Future<void> _joinAnchor() async {
    final engine = await RtcEngine.create(
      signaling: WhipWhepSignaling(
        whipUrl: _whipCtrl.text,
        whepUrl: _whepCtrl.text,
      ),
    );
    final session = await engine.join(
      roomId: _roomCtrl.text,
      role: RtcRole.anchor,
    );
    _eventSub = session.events.listen((event) {
      if (!mounted) return;
      setState(() => _log.add(_shortEvent(event)));
    });
    _statsSub = session.stats.listen((stats) {
      if (!mounted) return;
      setState(() => _latestStats = stats);
    });
    setState(() {
      _engine = engine;
      _session = session;
    });
    final publisher = session.localPublisher!;
    await publisher.startCamera();
    await _attachPreview(publisher);
    await publisher.startMic();
  }

  Future<void> _attachPreview(LocalPublisher publisher) async {
    try {
      await _previewRenderer.initialize();
      final track = publisher.cameraTrack;
      if (track != null) {
        await _previewRenderer.setSrcObject(stream: null, trackId: track.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _log.add('preview failed: $e'));
    }
  }

  Future<void> _subscribe() async {
    final session = _session;
    if (session == null) return;
    final sub = await session.subscribe(streamId: _streamCtrl.text);
    if (!mounted) return;
    setState(() => _subscriber = sub);
  }

  Future<void> _leave() async {
    await _session?.leave();
    if (!mounted) return;
    setState(() {
      _session = null;
      _subscriber = null;
      _latestStats = null;
    });
  }

  String _shortEvent(RtcEvent event) {
    if (event is RtcError) return 'ERR ${event.error.message}';
    if (event is RtcStatsUpdated) {
      final s = event.stats;
      return 'STATS ${s.streamId} ${s.bitrateKbps.toStringAsFixed(0)}kbps';
    }
    return event.runtimeType.toString();
  }
}
