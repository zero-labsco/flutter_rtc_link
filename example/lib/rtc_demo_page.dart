import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rtc_link/flutter_rtc_link.dart';
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
  // Default endpoints target a local MediaMTX instance (WHIP/WHEP on :8889).
  // Run MediaMTX, then `adb reverse tcp:8889 tcp:8889` so the phone reaches
  // the PC at 127.0.0.1:8889. The stream name lives in the URL path
  // (`rtc-link`); the `?stream=` query appended by the plugin is ignored by
  // MediaMTX. / 默认指向本地 MediaMTX（WHIP/WHEP 监听 :8889）。运行 MediaMTX 后执行
  // `adb reverse tcp:8889 tcp:8889`，手机即可经 127.0.0.1:8889 访问电脑。流名位于
  // URL 路径（`rtc-link`），插件追加的 `?stream=` 查询参数会被 MediaMTX 忽略。
  final _whipCtrl = TextEditingController(
    text: 'http://127.0.0.1:8889/rtc-link/whip',
  );
  final _whepCtrl = TextEditingController(
    text: 'http://127.0.0.1:8889/rtc-link/whep',
  );
  final _roomCtrl = TextEditingController(text: 'rtc-link');
  final _streamCtrl = TextEditingController(text: 'rtc-link');

  RtcEngine? _engine;
  RtcSession? _session;
  RemoteSubscriber? _subscriber;
  final _previewRenderer = RTCVideoRenderer();
  final List<String> _log = <String>[];
  RtcStats? _latestStats;
  StreamSubscription<RtcEvent>? _eventSub;
  StreamSubscription<RtcStats>? _statsSub;
  LocalPublisher? _publisher;
  CameraFacing? _lastFacing;

  @override
  void dispose() {
    _eventSub?.cancel();
    _statsSub?.cancel();
    _publisher?.status.removeListener(_onPublisherStatus);
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
                        ClarityLevel.p2160,
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
    // Ask for camera + mic up front so the OS prompts are explicit and a denial
    // is surfaced instead of failing silently inside startMic.
    // / 提前申请相机 + 麦克风权限，让系统弹窗明确、被拒时也能显式提示，而不是在
    // startMic 里静默失败。
    try {
      final results = await RtcPermissions.requestAll(<RtcPermission>[
        RtcPermission.camera,
        RtcPermission.microphone,
      ]);
      final denied = results.where((r) => !r.granted).toList();
      if (denied.isNotEmpty && mounted) {
        setState(
          () => _log.add(
            'permission denied: '
            '${denied.map((d) => d.capability.name).join(', ')}',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _log.add('permission request failed: $e'));
    }
    await publisher.startCamera();
    await _attachPreview(publisher);
    try {
      await publisher.startMic();
    } catch (e) {
      if (!mounted) return;
      setState(() => _log.add('mic failed: $e'));
    }
    _publisher = publisher;
    _lastFacing = publisher.status.value.facing;
    publisher.status.addListener(_onPublisherStatus);
  }

  Future<void> _attachPreview(LocalPublisher publisher) async {
    try {
      await _previewRenderer.initialize();
      // Render the camera's MediaStream directly — passing only a trackId does
      // not bind a stream on Android, which leaves the preview black.
      // / 直接渲染摄像头所在的 MediaStream；只传 trackId 在 Android 上不会绑定
      // stream，会导致预览黑屏。
      final stream = publisher.cameraStream;
      if (stream != null) {
        await _previewRenderer.setSrcObject(stream: stream);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _log.add('preview failed: $e'));
    }
  }

  void _onPublisherStatus() {
    final publisher = _publisher;
    if (publisher == null) return;
    final status = publisher.status.value;
    if (!status.cameraActive || status.facing == _lastFacing) return;
    _lastFacing = status.facing;
    _rebindPreview(publisher);
  }

  Future<void> _rebindPreview(LocalPublisher publisher) async {
    // switchCamera swaps the capture device and stops the old track, so the
    // preview renderer (still bound to the old MediaStream) must point at the
    // new one — otherwise the preview freezes on the stopped track.
    // / switchCamera 会换采集设备并停止旧轨道，预览渲染器仍绑在旧 MediaStream
    // 上，必须改指新的 stream，否则画面冻结在已停止的旧轨道上。
    try {
      final stream = publisher.cameraStream;
      if (stream != null) {
        await _previewRenderer.setSrcObject(stream: stream);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _log.add('preview rebind failed: $e'));
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
    _publisher?.status.removeListener(_onPublisherStatus);
    _publisher = null;
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
