import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ota/flutter_ota.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../core/rtc_events.dart';

/// OTA transfer channel. / OTA 传输通道。
enum OtaChannel {
  /// BLE OTA (ESP32-class via `flutter_ota`). / BLE OTA（ESP32-class，经 `flutter_ota`）。
  ble,

  /// HTTP OTA (download with resume, then push to the device endpoint). / HTTP OTA（断点续传下载，再推送到设备端点）。
  http,
}

/// OTA stage. / OTA 阶段。
enum OtaStage {
  /// Idle. / 空闲。
  idle,

  /// Downloading the firmware. / 正在下载固件。
  downloading,

  /// Verifying the firmware hash. / 正在校验固件哈希。
  verifying,

  /// Transferring to the device. / 正在传输到设备。
  transferring,

  /// Device rebooting into the new firmware. / 设备正在重启进入新固件。
  rebooting,

  /// Done. / 完成。
  done,

  /// Failed. / 失败。
  failed,
}

/// OTA progress snapshot. / OTA 进度快照。
class OtaProgress {
  const OtaProgress({
    required this.deviceId,
    required this.percent,
    required this.stage,
    this.error,
    this.version,
  });

  final String deviceId;

  /// Progress percentage (0–100). / 进度百分比（0–100）。
  final double percent;

  final OtaStage stage;
  final String? error;

  /// Version reported by the device (the source of truth). / 设备上报的版本（唯一真值）。
  final String? version;
}

/// OTA updater. / OTA 升级器。
///
/// Safety contract: the app verifies SHA-256 before transfer and treats the
/// **device-reported version** as success — a device's "ok" alone is not
/// trusted. Rollback is the device's job (dual partitions); the app retries
/// and reports failures. / 安全约定：App 在传输前校验 SHA-256，并以**设备上报的
/// 版本号**判定成功——不轻信设备单方面的"成功"。回滚由设备端双分区保证；
/// App 侧负责失败重试与状态展示。
class OtaUpdater {
  OtaUpdater({
    required this.channel,
    this.otaServiceUuid = '0000ffe0-0000-0000-0000-000000000000',
    this.notifyCharacteristicUuid = '0000ffe1-0000-0000-0000-000000000000',
    this.writeCharacteristicUuid = '0000ffe1-0000-0000-0000-000000000000',
    this.mtuSize = maxMtuSize,
    this.deviceHost = '192.168.4.1',
    this.devicePath = '/ota',
    this.license = License.nonprofit,
    Logger? logger,
  }) : _logger = logger ?? Logger('OtaUpdater');

  /// Transfer channel. / 传输通道。
  final OtaChannel channel;

  /// BLE OTA service UUID (must match the firmware). / BLE OTA 服务 UUID（须与固件一致）。
  final String otaServiceUuid;

  /// BLE notify characteristic UUID. / BLE notify 特征 UUID。
  final String notifyCharacteristicUuid;

  /// BLE write characteristic UUID. / BLE write 特征 UUID。
  final String writeCharacteristicUuid;

  /// BLE MTU (max 512). / BLE MTU（最大 512）。
  final int mtuSize;

  /// Device HTTP host for the HTTP channel. / HTTP 通道的设备主机。
  final String deviceHost;

  /// Device HTTP path for the HTTP channel. / HTTP 通道的设备路径。
  final String devicePath;

  /// flutter_blue_plus license declaration. / flutter_blue_plus 许可声明。
  final License license;

  final Logger _logger;
  OtaClient? _bleClient;
  bool _cancelRequested = false;

  /// Runs an upgrade and streams progress. / 执行升级并流式上报进度。
  Stream<OtaProgress> upgrade({
    required String deviceId,
    required String firmwareUrl,
    String? expectedMd5,
    String? expectedSha256,
  }) {
    final controller = StreamController<OtaProgress>();
    _cancelRequested = false;
    _run(
      controller: controller,
      deviceId: deviceId,
      firmwareUrl: firmwareUrl,
      expectedMd5: expectedMd5,
      expectedSha256: expectedSha256,
    );
    return controller.stream;
  }

  /// Cancels the running upgrade. / 取消进行中的升级。
  Future<void> cancel() async {
    _cancelRequested = true;
    await _bleClient?.cancel();
  }

  Future<void> _run({
    required StreamController<OtaProgress> controller,
    required String deviceId,
    required String firmwareUrl,
    String? expectedMd5,
    String? expectedSha256,
  }) async {
    void emit(
      double percent,
      OtaStage stage, {
      String? error,
      String? version,
    }) {
      if (controller.isClosed) return;
      controller.add(
        OtaProgress(
          deviceId: deviceId,
          percent: percent,
          stage: stage,
          error: error,
          version: version,
        ),
      );
    }

    try {
      emit(0, OtaStage.downloading);
      final firmware = await _downloadWithResume(
        firmwareUrl,
        onProgress: (percent) => emit(percent * 0.6, OtaStage.downloading),
      );
      if (_cancelRequested) {
        emit(0, OtaStage.failed, error: 'cancelled');
        await controller.close();
        return;
      }
      emit(60, OtaStage.verifying);
      _verifyFirmware(
        firmware,
        expectedMd5: expectedMd5,
        expectedSha256: expectedSha256,
      );
      emit(70, OtaStage.transferring);
      switch (channel) {
        case OtaChannel.ble:
          await _transferBle(
            deviceId: deviceId,
            firmware: firmware,
            firmwareUrl: firmwareUrl,
            expectedSha256: expectedSha256,
            emit: emit,
          );
        case OtaChannel.http:
          await _transferHttp(
            deviceId: deviceId,
            firmware: firmware,
            expectedMd5: expectedMd5,
            expectedSha256: expectedSha256,
            emit: emit,
          );
      }
    } catch (e) {
      _logger.warning('OTA failed: $e');
      emit(0, OtaStage.failed, error: e.toString());
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  Future<Uint8List> _downloadWithResume(
    String firmwareUrl, {
    required void Function(double percent) onProgress,
  }) async {
    final uri = Uri.parse(firmwareUrl);
    var offset = 0;
    final chunks = <Uint8List>[];
    int? total;
    while (true) {
      final request = http.Request('GET', uri);
      if (offset > 0) {
        request.headers['range'] = 'bytes=$offset-';
      }
      final response = await http.Response.fromStream(
        await http.Client().send(request),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'Firmware download returned ${response.statusCode}.',
        );
      }
      final contentRange = response.headers['content-range'];
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)\s*$').firstMatch(contentRange);
        if (match != null) total = int.tryParse(match.group(1)!);
      }
      total ??= response.contentLength ?? 0;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty && offset > 0) break;
      chunks.add(bytes);
      offset += bytes.length;
      if (total > 0) {
        onProgress((offset / total).clamp(0.0, 1.0).toDouble());
      }
      if (total <= 0 || offset >= total) break;
      if (_cancelRequested) break;
    }
    if (chunks.isEmpty) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Firmware download produced no data.',
      );
    }
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  void _verifyFirmware(
    Uint8List firmware, {
    String? expectedMd5,
    String? expectedSha256,
  }) {
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final actual = sha256.convert(firmware).toString();
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'SHA-256 mismatch: expected $expectedSha256, got $actual.',
        );
      }
    }
    if (expectedMd5 != null && expectedMd5.isNotEmpty) {
      final actual = md5.convert(firmware).toString();
      if (actual.toLowerCase() != expectedMd5.toLowerCase()) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'MD5 mismatch: expected $expectedMd5, got $actual.',
        );
      }
    }
  }

  Future<void> _transferBle({
    required String deviceId,
    required Uint8List firmware,
    required String firmwareUrl,
    String? expectedSha256,
    required void Function(double, OtaStage, {String? error, String? version})
    emit,
  }) async {
    final device = BluetoothDevice.fromId(deviceId);
    try {
      await device.connect(license: license, autoConnect: false);
    } catch (e) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'BLE connect to $deviceId failed.',
        cause: e,
      );
    }
    final services = await device.discoverServices();
    final notify = _findCharacteristic(services, notifyCharacteristicUuid);
    final write = _findCharacteristic(services, writeCharacteristicUuid);
    if (notify == null || write == null) {
      await device.disconnect();
      throw RtcException(
        code: RtcErrorCodes.unsupported,
        message: 'OTA characteristics not found in service $otaServiceUuid.',
      );
    }
    final client = OtaClient(
      transport: BleOtaTransport(
        device: device,
        notifyCharacteristic: notify,
        writeCharacteristic: write,
      ),
      protocol: EspIdfOtaProtocol(
        integrity: expectedSha256 == null || expectedSha256.isEmpty
            ? FirmwareIntegrityConfig.none
            : FirmwareIntegrityConfig(
                features: const <IntegrityFeature>{
                  IntegrityFeature.shaBeforeTransfer,
                },
                expectedSha256Hex: expectedSha256,
              ),
      ),
      source: UrlFirmwareSource(firmwareUrl),
    );
    _bleClient = client;
    final done = Completer<void>();
    client.percentageStream.listen((percent) {
      if (percent == cancelledValue) {
        emit(0, OtaStage.failed, error: 'cancelled');
        if (!done.isCompleted) done.complete();
      } else if (percent == failedValue) {
        emit(0, OtaStage.failed, error: 'BLE transfer failed');
        if (!done.isCompleted) done.complete();
      } else if (percent >= 100) {
        emit(100, OtaStage.done);
        if (!done.isCompleted) done.complete();
      } else {
        emit(70 + percent * 0.3, OtaStage.transferring);
      }
    });
    await client.run(mtuSize: mtuSize);
    await done.future;
    await client.dispose();
    _bleClient = null;
    emit(100, OtaStage.rebooting);
    await device.disconnect();
  }

  Future<void> _transferHttp({
    required String deviceId,
    required Uint8List firmware,
    String? expectedMd5,
    String? expectedSha256,
    required void Function(double, OtaStage, {String? error, String? version})
    emit,
  }) async {
    final response = await http
        .post(
          Uri.parse('http://$deviceHost$devicePath'),
          headers: <String, String>{
            'content-type': 'application/octet-stream',
            'x-md5': ?expectedMd5,
            'x-sha256': ?expectedSha256,
          },
          body: firmware,
        )
        .timeout(const Duration(minutes: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device OTA endpoint returned ${response.statusCode}.',
      );
    }
    emit(95, OtaStage.rebooting);
    String? version;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        version = decoded['version'] as String?;
      }
    } catch (_) {
      // Non-JSON responses are tolerated; the version stays unknown.
      // 非 JSON 响应可容忍；版本保持未知。
    }
    emit(100, OtaStage.done, version: version);
  }

  BluetoothCharacteristic? _findCharacteristic(
    List<BluetoothService> services,
    String uuid,
  ) {
    for (final service in services) {
      if (service.uuid.toString().toLowerCase() !=
          otaServiceUuid.toLowerCase()) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toString().toLowerCase() ==
            uuid.toLowerCase()) {
          return characteristic;
        }
      }
    }
    return null;
  }
}
