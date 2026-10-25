import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/rtc_events.dart';
import 'ble_device.dart';
import 'ble_link.dart';

/// GATT service UUID for the teleop control channel.
/// 遥测控制通道的 GATT 服务 UUID。
///
/// **Device firmware contract:** the robot must expose this service with the
/// two characteristics below. Replace these defaults (pass them to the
/// constructor) only if your firmware already reserves different UUIDs.
/// **设备固件契约：** 机器人必须暴露该服务，并包含以下两个特征。仅当固件已占用
/// 其他 UUID 时才通过构造函数覆盖。
const String kTeleopServiceUuid = '7e4e1700-cb3e-4b5f-9b2a-1c6e8d3f4a5b';

/// Command characteristic (phone → device, write). / 指令特征（手机 → 设备，可写）。
const String kTeleopCommandCharUuid = '7e4e1701-cb3e-4b5f-9b2a-1c6e8d3f4a5b';

/// Telemetry characteristic (device → phone, notify). / 遥测特征（设备 → 手机，notify）。
const String kTeleopTelemetryCharUuid = '7e4e1702-cb3e-4b5f-9b2a-1c6e8d3f4a5b';

/// `flutter_blue_plus` implementation of [BleLink].
/// [BleLink] 的 `flutter_blue_plus` 实现。
///
/// Reconnects automatically on a drop (capped, exponential backoff) so a brief
/// BLE glitch never silently kills the control link — the [RobotController]
/// watchdog stays the only hard stop. / 断线后自动重连（有上限、指数退避），
/// 短暂的 BLE 抖动不会悄悄掐断控制链路——硬性停车仍只由 [RobotController]
/// 看门狗负责。
class FlutterBluePlusBleLink implements BleLink {
  FlutterBluePlusBleLink(
    this.device, {
    this.serviceUuid = kTeleopServiceUuid,
    this.commandCharUuid = kTeleopCommandCharUuid,
    this.telemetryCharUuid = kTeleopTelemetryCharUuid,
    this.license = License.nonprofit,
    this.requestedMtu = 256,
    this.autoReconnect = true,
    this.maxReconnectAttempts = 10,
  });

  final BleDevice device;
  final String serviceUuid;
  final String commandCharUuid;
  final String telemetryCharUuid;
  final License license;
  final int requestedMtu;
  final bool autoReconnect;
  final int maxReconnectAttempts;

  BluetoothDevice? _bt;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _telemetryChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  Timer? _reconnectTimer;
  final StreamController<Map<String, dynamic>> _telemetryCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _stateCtrl = StreamController<bool>.broadcast();
  bool _userDisconnected = false;
  bool _connected = false;
  int _reconnectAttempts = 0;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Map<String, dynamic>> get telemetry => _telemetryCtrl.stream;

  @override
  Stream<bool> get connectionState => _stateCtrl.stream;

  @override
  Future<void> connect() async {
    _userDisconnected = false;
    _bt ??= BluetoothDevice(remoteId: DeviceIdentifier(device.id));
    await _open();
  }

  Future<void> _open() async {
    final bt = _bt!;
    _stateSub ??= bt.connectionState.listen(_onBleState);
    try {
      await bt.connect(license: license, autoConnect: false, mtu: requestedMtu);
      try {
        await bt.requestMtu(requestedMtu);
      } catch (_) {
        // Some stacks reject a second MTU request; ignore.
        // 部分协议栈会拒绝第二次 MTU 请求，忽略即可。
      }
      final services = await bt.discoverServices();
      BluetoothService? target;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          target = s;
          break;
        }
      }
      if (target == null) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message:
              'Teleop GATT service $serviceUuid not found on ${device.id}.',
        );
      }
      for (final c in target.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        if (uuid == commandCharUuid.toLowerCase()) {
          _commandChar = c;
        } else if (uuid == telemetryCharUuid.toLowerCase()) {
          _telemetryChar = c;
        }
      }
      if (_commandChar == null) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'Teleop command characteristic $commandCharUuid not found.',
        );
      }
      if (_telemetryChar != null) {
        await _telemetryChar!.setNotifyValue(true);
        _notifySub = _telemetryChar!.onValueReceived.listen(_onTelemetryBytes);
      }
      _connected = true;
      _reconnectAttempts = 0;
      _stateCtrl.add(true);
    } catch (e) {
      _connected = false;
      _stateCtrl.add(false);
      if (!_userDisconnected && autoReconnect) _scheduleReconnect();
      rethrow;
    }
  }

  void _onBleState(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.connected) {
      if (!_connected) {
        _connected = true;
        _stateCtrl.add(true);
        // Re-arm notifications in case the stack dropped them on reconnect.
        // 若重连后协议栈丢弃了订阅，重新开启通知。
        unawaited(_telemetryChar?.setNotifyValue(true));
      }
    } else if (state == BluetoothConnectionState.disconnected) {
      if (_connected) {
        _connected = false;
        _stateCtrl.add(false);
        _telemetryCtrl.add(const <String, dynamic>{'online': false});
        if (!_userDisconnected && autoReconnect) _scheduleReconnect();
      }
    }
  }

  void _onTelemetryBytes(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) _telemetryCtrl.add(data);
    } catch (_) {
      // Drop malformed frames; the next one will arrive shortly.
      // 丢弃残缺帧，下一帧很快会到。
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) return;
    final delay = Duration(
      milliseconds: 1000 * (1 << _reconnectAttempts).clamp(1, 8),
    );
    _reconnectAttempts += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_userDisconnected) return;
      try {
        await _open();
      } catch (_) {
        // _open already scheduled the next attempt on failure.
        // _open 失败时已安排下一次重连。
      }
    });
  }

  @override
  Future<bool> writeCommand(Map<String, dynamic> payload) async {
    final char = _commandChar;
    if (char == null || !_connected) return false;
    try {
      await char.write(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        withoutResponse: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _bt?.disconnect();
    } catch (_) {
      // Best effort. / 尽力而为。
    }
    _connected = false;
    _stateCtrl.add(false);
  }
}
