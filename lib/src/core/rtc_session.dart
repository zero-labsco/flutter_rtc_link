import 'package:flutter/foundation.dart';

import '../publishers/local_publisher.dart';
import '../subscribers/remote_subscriber.dart';
import 'rtc_events.dart';
import 'rtc_role.dart';
import 'rtc_stats.dart';

/// A remote stream available for subscription. / 可订阅的远端流。
class RemoteStream {
  const RemoteStream({
    required this.streamId,
    this.participantId,
    this.kinds = const <RtcTrackKind>{RtcTrackKind.video},
  });

  /// Stream (or track) id. / 流（或轨道）id。
  final String streamId;

  /// Owning participant, when the engine exposes one. / 所属参与者（引擎暴露时）。
  final String? participantId;

  /// Track kinds carried by this stream. / 该流承载的轨道类型。
  final Set<RtcTrackKind> kinds;

  /// Whether the stream carries video. / 是否携带视频。
  bool get hasVideo => kinds.contains(RtcTrackKind.video);

  /// Whether the stream carries audio. / 是否携带音频。
  bool get hasAudio => kinds.contains(RtcTrackKind.audio);

  @override
  String toString() =>
      'RemoteStream($streamId, participant: $participantId, kinds: $kinds)';
}

/// Session abstraction (room session or single-stream session).
/// 会话抽象（房间会话或单流会话）。
///
/// Three channels stay separated per the architecture contract:
/// media (WebRTC), control (MQTT/DataChannel) and business (HTTPS) never mix.
/// 按架构约定三条通道保持分离：媒体（WebRTC）、控制（MQTT / DataChannel）与
/// 业务（HTTPS）互不混用。
abstract class RtcSession {
  /// Room or session id. / 房间或会话 id。
  String get roomId;

  /// Current role (mutable through role transfer). / 当前角色（可经角色转接变更）。
  ValueNotifier<RtcRole> get role;

  /// Local publisher, present for publish-capable roles. / 本地推流器，可发布角色存在。
  LocalPublisher? get localPublisher;

  /// Stream of currently known remote streams. / 当前已知远端流的流。
  Stream<List<RemoteStream>> get remoteStreams;

  /// Session events (connection, tracks, roles, relay, errors). / 会话事件（连接、轨道、角色、转接、错误）。
  Stream<RtcEvent> get events;

  /// Periodic stats for all active tracks. / 所有活动轨道的周期性 stats。
  Stream<RtcStats> get stats;

  /// Subscribes to a remote stream. / 订阅一路远端流。
  Future<RemoteSubscriber> subscribe({
    required String streamId,
    VideoQuality quality = VideoQuality.auto,
  });

  /// Unsubscribes a stream. / 取消订阅一路流。
  Future<void> unsubscribe(String streamId);

  /// Leaves the session (keeps the engine reusable). / 离开会话（引擎可继续复用）。
  Future<void> leave();

  /// Disposes the session and all its tracks. / 释放会话及其所有轨道。
  Future<void> dispose();

  /// Emits a plugin-level event on the session event stream (permission
  /// denials, diagnostics hints, …). / 向会话事件流发送插件级事件
  /// （权限拒绝、诊断提示等）。
  void emit(RtcEvent event);
}
