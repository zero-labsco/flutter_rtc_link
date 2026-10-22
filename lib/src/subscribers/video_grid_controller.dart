import 'package:flutter/foundation.dart';

import '../core/rtc_session.dart';
import '../core/rtc_stats.dart';

/// Layout mode for multi-stream display. / 多路视频显示的布局模式。
enum LayoutMode {
  /// Equal-size grid. / 等分网格。
  grid,

  /// Main stream + thumbnails. / 主画面 + 缩略图。
  pip,

  /// Single main stream only. / 仅主画面。
  speaker,
}

/// Immutable snapshot of the grid state. / 网格状态的不可变快照。
class GridState {
  const GridState({
    this.streams = const <RemoteStream>[],
    this.mainStreamId,
    this.layout = LayoutMode.grid,
    this.maxVisible = 4,
    this.globalClarity = ClarityLevel.auto,
    this.clarityOverrides = const <String, ClarityLevel>{},
  });

  /// Known remote streams. / 已知远端流。
  final List<RemoteStream> streams;

  /// Main stream id (first visible stream when unset). / 主画面流 id（未设置时为第一个可见流）。
  final String? mainStreamId;

  /// Layout mode. / 布局模式。
  final LayoutMode layout;

  /// Maximum simultaneously visible streams. / 最大同屏可见流数量。
  final int maxVisible;

  /// Global clarity applied to streams without an override. / 应用到无覆盖流之上的全局清晰度。
  final ClarityLevel globalClarity;

  /// Per-stream clarity overrides. / 每路流的清晰度覆盖。
  final Map<String, ClarityLevel> clarityOverrides;

  /// Streams to render (main first, capped by [maxVisible]). / 需要渲染的流（主画面优先，受 [maxVisible] 限制）。
  List<RemoteStream> get visibleStreams {
    final ordered = <RemoteStream>[];
    final main = mainStream;
    if (main != null) ordered.add(main);
    for (final stream in streams) {
      if (ordered.length >= maxVisible) break;
      if (main != null && stream.streamId == main.streamId) continue;
      ordered.add(stream);
    }
    return ordered;
  }

  /// The main stream object, if any. / 主画面流对象（如有）。
  RemoteStream? get mainStream {
    if (streams.isEmpty) return null;
    if (mainStreamId != null) {
      for (final stream in streams) {
        if (stream.streamId == mainStreamId) return stream;
      }
    }
    return streams.first;
  }

  /// Thumbnail streams (everything except the main stream).
  /// 缩略图流（主画面之外的全部）。
  ///
  /// The speaker layout is single-view, so it has no thumbnails.
  /// speaker 布局是单画面，没有缩略图。
  List<RemoteStream> get thumbnailStreams {
    if (layout == LayoutMode.speaker) return const <RemoteStream>[];
    final main = mainStream;
    if (main == null) return const <RemoteStream>[];
    return streams
        .where((s) => s.streamId != main.streamId)
        .take(maxVisible - 1 < 0 ? 0 : maxVisible - 1)
        .toList();
  }

  /// Effective clarity for a stream (override wins). / 某路流的生效清晰度（覆盖优先）。
  ClarityLevel clarityFor(String streamId) {
    return clarityOverrides[streamId] ?? globalClarity;
  }

  GridState copyWith({
    List<RemoteStream>? streams,
    String? mainStreamId,
    bool clearMain = false,
    LayoutMode? layout,
    int? maxVisible,
    ClarityLevel? globalClarity,
    Map<String, ClarityLevel>? clarityOverrides,
  }) {
    return GridState(
      streams: streams ?? this.streams,
      mainStreamId: clearMain ? null : (mainStreamId ?? this.mainStreamId),
      layout: layout ?? this.layout,
      maxVisible: maxVisible ?? this.maxVisible,
      globalClarity: globalClarity ?? this.globalClarity,
      clarityOverrides: clarityOverrides ?? this.clarityOverrides,
    );
  }
}

/// Pure-Dart controller for multi-stream layout and clarity switching.
/// 纯 Dart 的多路画面布局与清晰度切换控制器。
///
/// No WebRTC or Flutter widget dependencies — feed it
/// `session.remoteStreams` and read [state] from the UI.
/// 不依赖 WebRTC 或 Flutter widget——把 `session.remoteStreams` 喂给它，
/// UI 读取 [state]。
class VideoGridController extends ValueNotifier<GridState> {
  VideoGridController({
    int maxVisible = 4,
    LayoutMode layout = LayoutMode.grid,
    ClarityLevel globalClarity = ClarityLevel.auto,
  }) : super(
         GridState(
           maxVisible: maxVisible,
           layout: layout,
           globalClarity: globalClarity,
         ),
       );

  /// Replaces the stream list, keeping the main selection when possible.
  /// 替换流列表，尽可能保留主画面选择。
  void setStreams(List<RemoteStream> streams) {
    final main = value.mainStreamId;
    final mainStillThere = streams.any((s) => s.streamId == main);
    value = value.copyWith(
      streams: List<RemoteStream>.unmodifiable(streams),
      clearMain: !mainStillThere,
    );
  }

  /// Adds or updates a stream. / 新增或更新一路流。
  void upsertStream(RemoteStream stream) {
    final streams =
        value.streams.where((s) => s.streamId != stream.streamId).toList()
          ..add(stream);
    setStreams(streams);
  }

  /// Removes a stream. / 移除一路流。
  void removeStream(String streamId) {
    final streams = value.streams.where((s) => s.streamId != streamId).toList();
    final isMain = value.mainStreamId == streamId;
    value = value.copyWith(
      streams: List<RemoteStream>.unmodifiable(streams),
      clearMain: isMain,
    );
  }

  /// Selects the main stream. / 选择主画面流。
  void setMain(String streamId) {
    if (!value.streams.any((s) => s.streamId == streamId)) return;
    value = value.copyWith(mainStreamId: streamId);
  }

  /// Switches the layout mode. / 切换布局模式。
  void setLayout(LayoutMode mode) {
    value = value.copyWith(layout: mode);
  }

  /// Caps the number of visible streams. / 限制可见流数量。
  void setMaxVisible(int count) {
    if (count < 1) return;
    value = value.copyWith(maxVisible: count);
  }

  /// Sets clarity for all streams at once. / 一次性设置所有流的清晰度。
  void setGlobalClarity(ClarityLevel level) {
    value = value.copyWith(
      globalClarity: level,
      clarityOverrides: const <String, ClarityLevel>{},
    );
  }

  /// Sets clarity for one stream only. / 仅为一路流设置清晰度。
  void setStreamClarity(String streamId, ClarityLevel level) {
    final overrides = Map<String, ClarityLevel>.from(value.clarityOverrides);
    overrides[streamId] = level;
    value = value.copyWith(clarityOverrides: overrides);
  }

  /// Applies clarity to the visible subscribers.
  /// 将清晰度应用到可见订阅器上。
  ///
  /// [apply] typically calls `RemoteSubscriber.setClarity`.
  /// [apply] 通常调用 `RemoteSubscriber.setClarity`。
  Future<void> applyClarity(
    Future<void> Function(String streamId, ClarityLevel level) apply,
  ) async {
    for (final stream in value.visibleStreams) {
      await apply(stream.streamId, value.clarityFor(stream.streamId));
    }
  }
}
