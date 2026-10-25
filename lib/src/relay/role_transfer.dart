import 'dart:convert';

import '../core/rtc_events.dart';
import '../core/rtc_role.dart';
import '../core/rtc_session.dart';
import '../engines/livekit_engine.dart';

/// Topic used for role-transfer notifications over the data channel.
/// 角色转接通知使用的数据通道主题。
const String kRoleTransferTopic = 'rtc_link:role';

/// Payload of a role-transfer notification. / 角色转接通知的内容。
class RoleTransferNotice {
  const RoleTransferNotice({
    required this.action,
    required this.targetIdentity,
    required this.role,
  });

  /// `promote`, `handover` or `demote`. / `promote`、`handover` 或 `demote`。
  final String action;

  /// Target identity. / 目标身份。
  final String targetIdentity;

  /// Role name after the transfer. / 转接后的角色名。
  final String role;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'action': action,
    'targetIdentity': targetIdentity,
    'role': role,
  };

  static RoleTransferNotice? tryDecode(List<int> data) {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      return RoleTransferNotice(
        action: decoded['action'] as String? ?? '',
        targetIdentity: decoded['targetIdentity'] as String? ?? '',
        role: decoded['role'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Backend that issues refreshed room tokens with new grants.
/// 签发带新授权的刷新令牌的后端。
///
/// Role transfer is a **server-side permission change**: the target needs a
/// new token whose grants allow publishing. The plugin never mints tokens —
/// implement this against your auth service.
/// 角色转接是**服务端权限变更**：目标需要一张允许发布的新令牌。插件从不签发
/// 令牌——请针对你的鉴权服务实现该接口。
abstract class RoleGrantBackend {
  /// Grants or revokes publish rights for [identity]. / 为 [identity] 授予 / 收回发布权。
  Future<void> setPublishGrant({
    required String roomId,
    required String identity,
    required bool canPublish,
  });
}

/// Role transfer (identity handover), separate from stream relay.
/// 角色转接（身份交接），与流转接分开实现。
///
/// The backend grant change is the source of truth; the plugin notifies the
/// target over the control path (LiveKit data channel) and the session emits
/// [RtcRoleChanged] once the server confirms the new permissions.
/// 后端授权变更是唯一真值；插件通过控制通道（LiveKit 数据通道）通知目标，
/// 服务端确认新权限后由会话发出 [RtcRoleChanged]。
class RoleTransfer {
  const RoleTransfer._();

  /// Promotes a viewer to co-host (audience hand-raise).
  /// 将观众提升为连麦嘉宾（观众举手上麦）。
  static Future<void> promote(
    RtcSession session, {
    required String targetIdentity,
    required RoleGrantBackend backend,
  }) async {
    await backend.setPublishGrant(
      roomId: session.roomId,
      identity: targetIdentity,
      canPublish: true,
    );
    await _notify(
      session,
      RoleTransferNotice(
        action: 'promote',
        targetIdentity: targetIdentity,
        role: RtcRole.coHost.label,
      ),
    );
  }

  /// Hands the anchor role over to [targetIdentity]; the previous anchor
  /// becomes a viewer. / 将牵头角色交接给 [targetIdentity]；原牵头降为观众。
  static Future<void> handover(
    RtcSession session, {
    required String targetIdentity,
    required RoleGrantBackend backend,
    String? previousAnchorIdentity,
  }) async {
    await backend.setPublishGrant(
      roomId: session.roomId,
      identity: targetIdentity,
      canPublish: true,
    );
    final previous = previousAnchorIdentity ?? await _localIdentity(session);
    if (previous != null && previous != targetIdentity) {
      try {
        await backend.setPublishGrant(
          roomId: session.roomId,
          identity: previous,
          canPublish: false,
        );
      } catch (e) {
        // Leaving the first grant in place would publish two anchors at once,
        // so roll it back before surfacing the failure. /
        // 保留第一次授权会导致两个牵头同时推流，因此在抛出前先回滚。
        await _rollbackGrant(
          session,
          backend: backend,
          identity: targetIdentity,
          canPublish: false,
        );
        rethrow;
      }
    }
    await _notify(
      session,
      RoleTransferNotice(
        action: 'handover',
        targetIdentity: targetIdentity,
        role: RtcRole.anchor.label,
      ),
    );
    if (previous != null && previous != targetIdentity) {
      await _notify(
        session,
        RoleTransferNotice(
          action: 'demote',
          targetIdentity: previous,
          role: RtcRole.viewer.label,
        ),
      );
    }
  }

  /// Demotes a co-host back to viewer. / 将连麦嘉宾降回观众。
  static Future<void> demote(
    RtcSession session, {
    required String targetIdentity,
    required RoleGrantBackend backend,
  }) async {
    await backend.setPublishGrant(
      roomId: session.roomId,
      identity: targetIdentity,
      canPublish: false,
    );
    await _notify(
      session,
      RoleTransferNotice(
        action: 'demote',
        targetIdentity: targetIdentity,
        role: RtcRole.viewer.label,
      ),
    );
  }

  /// Sends the notice over the control path when the engine supports it.
  /// 引擎支持时通过控制通道发送通知。
  static Future<void> _notify(
    RtcSession session,
    RoleTransferNotice notice,
  ) async {
    if (session is! LiveKitSession) {
      // WHIP/WHEP has no room semantics: the backend grant is the only signal,
      // apps should mirror it into their own signaling channel.
      // WHIP/WHEP 没有房间语义：后端授权是唯一信号，App 应自行镜像到自己的信令通道。
      return;
    }
    final local = session.room.localParticipant;
    if (local == null) return;
    try {
      await local.publishData(
        utf8.encode(jsonEncode(notice.toJson())),
        reliable: true,
        topic: kRoleTransferTopic,
        destinationIdentities: <String>[notice.targetIdentity],
      );
    } catch (e) {
      session.emit(
        RtcError(
          error: RtcException(
            code: RtcErrorCodes.signalingFailed,
            message: 'Failed to send role-transfer notice: $e',
            cause: e,
          ),
        ),
      );
    }
  }

  /// Best-effort rollback of a grant whose follow-up step failed.
  /// 对后续步骤失败的授权做尽力回滚。
  static Future<void> _rollbackGrant(
    RtcSession session, {
    required RoleGrantBackend backend,
    required String identity,
    required bool canPublish,
  }) async {
    try {
      await backend.setPublishGrant(
        roomId: session.roomId,
        identity: identity,
        canPublish: canPublish,
      );
    } catch (e) {
      // The server already rejected the pairing change; the caller sees the
      // original error and the mismatch shows up at the next permission sync.
      // 服务端已拒绝该次配对变更；调用方看到的是原始错误，不一致会在下一次
      // 权限同步时暴露。
      session.emit(
        RtcError(
          error: RtcException(
            code: RtcErrorCodes.signalingFailed,
            message: 'Failed to roll back the publish grant for $identity: $e',
            cause: e,
          ),
        ),
      );
    }
  }

  static Future<String?> _localIdentity(RtcSession session) async {
    if (session is LiveKitSession) {
      return session.room.localParticipant?.identity;
    }
    return null;
  }
}
