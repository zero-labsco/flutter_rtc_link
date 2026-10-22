import 'package:permission_handler/permission_handler.dart';

import '../core/rtc_events.dart';
import '../core/rtc_session.dart';

/// Permission capability covered by the plugin. / 插件覆盖的权限能力。
///
/// Maps onto the platform pitfalls documented in the README: Android 13+
/// nearby Wi-Fi devices, Android 14+ foreground-service microphone, iOS NFC
/// entitlement. / 对应 README 中的平台权限坑：Android 13+ 附近 Wi-Fi 设备、
/// Android 14+ 前台服务麦克风、iOS NFC entitlement。
enum RtcPermission {
  /// Camera. / 摄像头。
  camera,

  /// Microphone. / 麦克风。
  microphone,

  /// BLE scan (Android 12+). / BLE 扫描（Android 12+）。
  bluetoothScan,

  /// BLE connect (Android 12+). / BLE 连接（Android 12+）。
  bluetoothConnect,

  /// Nearby Wi-Fi devices (Android 13+, `neverForLocation`). / 附近 Wi-Fi 设备（Android 13+，`neverForLocation`）。
  nearbyWifiDevices,

  /// Notifications (Android 13+). / 通知（Android 13+）。
  notifications,

  /// Location (legacy Wi-Fi scanning on Android 12-). / 定位（Android 12- 旧版 Wi-Fi 扫描）。
  locationWhenInUse,
}

/// Result of one capability request. / 单个能力请求的结果。
class PermissionResult {
  const PermissionResult({
    required this.capability,
    required this.granted,
    this.permanentlyDenied = false,
  });

  final RtcPermission capability;

  /// Whether the capability was granted. / 该能力是否被授予。
  final bool granted;

  /// Whether it was permanently denied ("don't ask again"). / 是否被永久拒绝（"不再询问"）。
  final bool permanentlyDenied;
}

/// Unified permission gate: request on demand, never crash on denial.
/// 统一权限入口：按需申请，被拒不崩溃。
///
/// Denials degrade the feature and surface as
/// [RtcEvent.permissionDenied] — see `RtcPermissions.ensureForSession`.
/// 被拒时功能降级并通过 [RtcEvent.permissionDenied] 上报——见
/// `RtcPermissions.ensureForSession`。
class RtcPermissions {
  const RtcPermissions._();

  /// Requests every capability in [capabilities] (grouped, on demand).
  /// 申请 [capabilities] 中的全部能力（分组、按需）。
  static Future<List<PermissionResult>> requestAll(
    List<RtcPermission> capabilities,
  ) async {
    final results = <PermissionResult>[];
    for (final capability in capabilities) {
      final permission = _map(capability);
      if (permission == null) {
        // Capability not applicable on this platform: treat as granted so the
        // feature keeps working (e.g. Wi-Fi APIs on iOS are query-only).
        // 该平台不适用的能力：视为已授予，功能继续可用（如 iOS 的 Wi-Fi API 仅查询级）。
        results.add(PermissionResult(capability: capability, granted: true));
        continue;
      }
      final status = await permission.request();
      results.add(
        PermissionResult(
          capability: capability,
          granted: status.isGranted || status.isLimited,
          permanentlyDenied: status.isPermanentlyDenied,
        ),
      );
    }
    return results;
  }

  /// Pre-checks a capability without prompting. / 预检能力，不弹窗。
  static Future<bool> check(RtcPermission capability) async {
    final permission = _map(capability);
    if (permission == null) return true;
    final status = await permission.status;
    return status.isGranted || status.isLimited;
  }

  /// Requests the capabilities and reports denials on the session event
  /// stream. Returns whether every capability was granted.
  /// 申请能力并把拒绝情况上报到会话事件流。返回是否全部授予。
  static Future<bool> ensureForSession(
    RtcSession session,
    List<RtcPermission> capabilities,
  ) async {
    final results = await requestAll(capabilities);
    var allGranted = true;
    for (final result in results) {
      if (result.granted) continue;
      allGranted = false;
      _emitDenied(session, result);
    }
    return allGranted;
  }

  /// Opens the app settings page (for permanent denials). / 打开应用设置页（用于永久拒绝）。
  static Future<bool> openSettings() => openAppSettings();

  static void _emitDenied(RtcSession session, PermissionResult result) {
    session.emit(
      RtcPermissionDenied(
        capability: result.capability.name,
        permanently: result.permanentlyDenied,
      ),
    );
  }

  static Permission? _map(RtcPermission capability) {
    switch (capability) {
      case RtcPermission.camera:
        return Permission.camera;
      case RtcPermission.microphone:
        return Permission.microphone;
      case RtcPermission.bluetoothScan:
        return Permission.bluetoothScan;
      case RtcPermission.bluetoothConnect:
        return Permission.bluetoothConnect;
      case RtcPermission.nearbyWifiDevices:
        return Permission.nearbyWifiDevices;
      case RtcPermission.notifications:
        return Permission.notification;
      case RtcPermission.locationWhenInUse:
        return Permission.locationWhenInUse;
    }
  }
}
