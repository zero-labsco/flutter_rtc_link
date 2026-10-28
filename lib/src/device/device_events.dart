import 'diagnostics.dart';
import 'ota_updater.dart';
import 'provisioning.dart';

/// Sealed hierarchy of device-management events (independent stream).
/// 设备管理事件的密封层级（独立事件流）。
///
/// This lives in the device module — not in `core/` — so that `core` stays a
/// dependency-free shared kernel and the device module never has to reach into
/// robot teleoperation (or vice versa) just to emit an event.
/// 本文件位于 device 模块而非 `core/`：这样 `core` 才能保持零依赖的共享内核，
/// 设备管理模块也不必为了发一个事件就依赖机器人遥控（反之亦然）。
sealed class DeviceEvent {
  const DeviceEvent();
}

/// Provisioning state changed (including failure with classified reason).
/// 配网状态变化（含带分类原因的失败）。
final class ProvisioningStateChanged extends DeviceEvent {
  const ProvisioningStateChanged({
    required this.state,
    required this.method,
    this.reason,
    this.deviceId,
  });

  /// Current state. / 当前状态。
  final ProvisioningState state;

  /// Method used or attempted. / 正在使用或尝试的方式。
  final ProvisionMethod method;

  /// Failure classification, when [state] is failed. / 失败分类（[state] 为 failed 时）。
  final ProvisionFailureReason? reason;

  /// Device id if known. / 设备 id（如已知）。
  final String? deviceId;
}

/// OTA progress update (wraps the updater's [OtaProgress] snapshot).
/// OTA 进度更新（包装升级器的 [OtaProgress] 快照）。
final class OtaProgressChanged extends DeviceEvent {
  const OtaProgressChanged({required this.progress});

  /// Progress snapshot. / 进度快照。
  final OtaProgress progress;
}

/// OTA completed; trust the reported version, not the device's "success".
/// OTA 完成；以版本号上报为准，不轻信设备返回的"成功"。
final class OtaCompleted extends DeviceEvent {
  const OtaCompleted({required this.deviceId, required this.version});

  /// Device id. / 设备 id。
  final String deviceId;

  /// New firmware version reported by the device. / 设备上报的新固件版本。
  final String version;
}

/// OTA failed. / OTA 失败。
final class OtaFailed extends DeviceEvent {
  const OtaFailed({
    required this.deviceId,
    required this.error,
    this.rolledBack = false,
  });

  /// Device id. / 设备 id。
  final String deviceId;

  /// Error description. / 错误描述。
  final String error;

  /// Whether the device rolled back to the old firmware. / 设备是否已回滚到旧固件。
  final bool rolledBack;
}

/// A batch of device logs was uploaded. / 一批设备日志已上传。
final class LogBatchUploaded extends DeviceEvent {
  const LogBatchUploaded({required this.deviceId, required this.count});

  /// Device id. / 设备 id。
  final String deviceId;

  /// Number of log entries uploaded. / 上传的日志条数。
  final int count;
}

/// Diagnostics report is ready. / 诊断报告已生成。
final class DiagnosticsReportReady extends DeviceEvent {
  const DiagnosticsReportReady({required this.report});

  /// The generated report. / 生成的报告。
  final DiagnosticReport report;
}
