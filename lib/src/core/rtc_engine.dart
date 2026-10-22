import 'package:logging/logging.dart';

import '../engines/livekit_engine.dart';
import '../engines/whip_whep_engine.dart';
import 'rtc_events.dart';
import 'rtc_role.dart';
import 'rtc_session.dart';
import 'rtc_signaling.dart';

/// Engine kind. / 引擎类型。
enum RtcEngineType {
  /// `flutter_webrtc` bare engine over WHIP/WHEP. / 基于 `flutter_webrtc` 的裸引擎，走 WHIP/WHEP。
  whipWhep,

  /// `livekit_client` room engine. / 基于 `livekit_client` 的房间引擎。
  livekit,
}

/// Engine abstraction with a factory that picks the implementation from the
/// signaling configuration (dual-engine, unified entry).
/// 引擎抽象 + 工厂：按信令配置选择实现（双引擎、统一入口）。
abstract class RtcEngine {
  const RtcEngine();

  /// Engine kind. / 引擎类型。
  RtcEngineType get type;

  /// Joins a room (or a single-stream session for WHIP/WHEP viewers).
  /// 加入房间（WHIP/WHEP 观众端为单流会话）。
  Future<RtcSession> join({
    required String roomId,
    required RtcRole role,
    String? identity,
  });

  /// Engine-level events (engine failures, token refresh problems). / 引擎级事件（引擎失败、令牌刷新问题）。
  Stream<RtcEvent> get events;

  /// Disposes the engine. / 释放引擎。
  Future<void> dispose();

  /// Creates the engine matching [signaling]. / 按 [signaling] 创建匹配的引擎。
  ///
  /// ```dart
  /// final engine = await RtcEngine.create(
  ///   signaling: WhipWhepSignaling(
  ///     whipUrl: 'https://srs.example.com/rtc/v1/whip/',
  ///     whepUrl: 'https://srs.example.com/rtc/v1/whep/',
  ///     iceServers: [IceServer(urls: 'turn:turn.example.com:3478', username: '..', credential: '..')],
  ///   ),
  /// );
  /// ```
  static Future<RtcEngine> create({
    required RtcSignaling signaling,
    String? identity,
    Logger? logger,
  }) async {
    switch (signaling) {
      case WhipWhepSignaling whipWhep:
        return WhipWhepEngine(whipWhep, identity: identity, logger: logger);
      case LiveKitSignaling livekit:
        return LiveKitEngine(livekit, identity: identity, logger: logger);
    }
  }
}
