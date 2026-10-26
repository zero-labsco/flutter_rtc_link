import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../robot/ble/ble_device.dart';

/// Clean, protocol-agnostic view of a GATT characteristic. / 与具体协议无关的
/// GATT 特征视图（不暴露任何 `flutter_blue_plus` 类型）。
class BleGattCharacteristic {
  const BleGattCharacteristic({
    required this.uuid,
    required this.canRead,
    required this.canWrite,
    required this.canWriteWithoutResponse,
    required this.canNotify,
    required this.canIndicate,
  });

  /// Lower-cased UUID string. / 小写 UUID 字符串。
  final String uuid;
  final bool canRead;
  final bool canWrite;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;
}

/// Clean, protocol-agnostic view of a GATT service. / 与具体协议无关的
/// GATT 服务视图。
class BleGattService {
  const BleGattService({required this.uuid, required this.characteristics});

  /// Lower-cased UUID string. / 小写 UUID 字符串。
  final String uuid;
  final List<BleGattCharacteristic> characteristics;
}

/// Internal bookkeeping for an active notification subscription. /
/// 一个活跃通知订阅的内部记账。
class _Subscription {
  _Subscription(this.controller, this.underlying);

  final StreamController<List<int>> controller;
  StreamSubscription<List<int>> underlying;

  Future<void> dispose() async {
    await underlying.cancel();
    if (!controller.isClosed) await controller.close();
  }
}

/// Protocol-agnostic BLE GATT client for any device (speaker, sensor, …).
/// 面向任意设备的、与协议无关的 BLE GATT 客户端（音响、传感器等）。
///
/// Unlike [BleTeleopChannel] (robot-only) this client makes no service or
/// protocol assumptions — it just connects, discovers, and exposes raw
/// read / write / notify. A speaker / sensor / peripheral project can use it
/// directly without pulling in the robot teleop contract. Built on
/// `flutter_blue_plus`. / 与仅限机器人的 [BleTeleopChannel] 不同，本客户端不做
/// 任何服务 / 协议假设——只负责连接、发现并暴露原始的读 / 写 / 通知能力。音响 /
/// 传感器 / 外设类项目可直接使用，无需引入机器人遥测契约。基于
/// `flutter_blue_plus` 实现。
///
/// Call [dispose] when the client is no longer needed so every stream and the
/// connection are released. / 不再使用时请调用 [dispose]，以释放所有流与连接。
class BleGattClient {
  BleGattClient(
    this.device, {
    this.license = License.nonprofit,
    this.mtu = 256,
    this.autoReconnect = false,
    this.maxReconnectAttempts = 10,
  });

  /// The device to connect to. / 目标设备。
  final BleDevice device;

  /// `flutter_blue_plus` license declaration (commercial use needs the paid
  /// license). / `flutter_blue_plus` 许可声明（商业用途需购买付费许可）。
  final License license;

  /// Requested MTU (max 512). / 请求的 MTU（最大 512）。
  final int mtu;

  /// Reconnect automatically on a drop (capped, exponential backoff). /
  /// 断线后自动重连（有上限、指数退避）。
  final bool autoReconnect;

  /// Maximum automatic reconnect attempts. / 自动重连的最大次数。
  final int maxReconnectAttempts;

  BluetoothDevice? _bt;
  final Map<String, BluetoothCharacteristic> _chars =
      <String, BluetoothCharacteristic>{};
  final Map<String, _Subscription> _subs = <String, _Subscription>{};
  final StreamController<bool> _stateCtrl = StreamController<bool>.broadcast();
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  Timer? _reconnectTimer;
  bool _connected = false;
  bool _userDisconnected = false;
  bool _opening = false;
  int _reconnectAttempts = 0;

  /// Current connection state. / 当前连接状态。
  bool get isConnected => _connected;

  /// Stream of connection-state changes (true = connected). /
  /// 连接状态变化流（true = 已连接）。
  Stream<bool> get connectionState => _stateCtrl.stream;

  /// Connects and negotiates the MTU. / 连接并协商 MTU。
  ///
  /// Cancels any pending reconnect timer so a manual connect wins. /
  /// 会取消待执行的重连定时器，使手动连接优先。
  Future<void> connect() async {
    _userDisconnected = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _bt ??= BluetoothDevice(remoteId: DeviceIdentifier(device.id));
    await _open();
  }

  Future<void> _open() async {
    // Guard against concurrent connects (manual connect vs reconnect timer).
    // / 防止并发连接（手动连接与重连定时器撞车）。
    if (_opening) return;
    _opening = true;
    final bt = _bt!;
    _stateSub ??= bt.connectionState.listen(_onBleState);
    try {
      await bt.connect(license: license, autoConnect: false, mtu: mtu);
      // If disconnect() raced in while connecting, abort immediately so we do
      // not leave a live, unmanaged link. / 若连接途中被 disconnect() 抢先，立即
      // 中止，避免留下无人管理的活跃连接。
      if (_userDisconnected) {
        try {
          await bt.disconnect();
        } catch (_) {
          // Best effort. / 尽力而为。
        }
        _setConnected(false);
        return;
      }
      try {
        await bt.requestMtu(mtu);
      } catch (_) {
        // Some stacks reject a second MTU request; ignore.
        // 部分协议栈会拒绝第二次 MTU 请求，忽略即可。
      }
      _reconnectAttempts = 0;
      _setConnected(true);
      // Refresh cached characteristic handles after every (re)connect: they are
      // invalidated on a drop, so read / write would otherwise target stale
      // handles even when nothing is subscribed. /
      // 每次（重）连后刷新缓存的特征句柄：断线会使其失效，否则即使没有订阅，
      // read / write 也会打向陈旧句柄。
      try {
        await discoverServices();
      } catch (_) {
        // Best effort: read / write surface their own errors.
        // 尽力而为：读 / 写会自行上报错误。
      }
      // Re-establish notifications after a (re)connect: the CCCD must be
      // re-enabled. / 重连后重新建立通知：CCCD 需重新开启。
      if (_subs.isNotEmpty) {
        try {
          await _rebindSubscriptions();
        } catch (_) {
          // Non-fatal: the link is up; individual subs surface their own errors.
          // 非致命：链路已通；各订阅自行上报错误。
        }
      }
    } catch (e) {
      _onConnectionLost();
      rethrow;
    } finally {
      _opening = false;
    }
  }

  void _onBleState(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.connected) {
      _setConnected(true);
    } else if (state == BluetoothConnectionState.disconnected) {
      // Only react on a real transition. / 仅在真实状态跳变时处理。
      if (!_connected) return;
      _onConnectionLost();
    }
  }

  /// Handles a transition to "disconnected": schedule a reconnect when allowed,
  /// otherwise tear down active subscriptions so consumers stop hanging. /
  /// 处理"已断开"跳变：允许时安排重连，否则拆除活跃订阅，避免消费者卡死。
  void _onConnectionLost() {
    _setConnected(false);
    if (_userDisconnected || !autoReconnect) {
      _teardownSubs();
      return;
    }
    if (!_scheduleReconnect()) _teardownSubs();
  }

  bool _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) return false;
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
    return true;
  }

  /// Discovers GATT services and returns a clean, protocol-agnostic view. /
  /// 发现 GATT 服务，返回干净、与协议无关的视图。
  ///
  /// Must be called (or re-called after a reconnect) before [read] / [write] /
  /// [subscribe]. / 在 [read] / [write] / [subscribe] 之前须调用（重连后亦须重新
  /// 调用，因为服务句柄已失效）。
  Future<List<BleGattService>> discoverServices() async {
    final bt = _bt;
    if (bt == null || !_connected) {
      throw StateError('BleGattClient is not connected.');
    }
    final services = await bt.discoverServices();
    // Build into a temp map first so _chars is never transiently empty while a
    // concurrent read / write resolves it. / 先填入临时表，避免并发读写期间
    // _chars 短暂为空。
    final newChars = <String, BluetoothCharacteristic>{};
    final result = <BleGattService>[];
    for (final s in services) {
      final chars = <BleGattCharacteristic>[];
      for (final c in s.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        newChars[uuid] = c;
        chars.add(
          BleGattCharacteristic(
            uuid: uuid,
            canRead: c.properties.read,
            canWrite: c.properties.write,
            canWriteWithoutResponse: c.properties.writeWithoutResponse,
            canNotify: c.properties.notify,
            canIndicate: c.properties.indicate,
          ),
        );
      }
      result.add(
        BleGattService(
          uuid: s.uuid.toString().toLowerCase(),
          characteristics: chars,
        ),
      );
    }
    _chars
      ..clear()
      ..addAll(newChars);
    return result;
  }

  void _ensureConnected() {
    if (!_connected) {
      throw StateError('BleGattClient is not connected.');
    }
  }

  BluetoothCharacteristic _resolve(String charUuid) {
    final c = _chars[charUuid.toLowerCase()];
    if (c == null) {
      throw StateError(
        'Characteristic $charUuid not discovered. Call discoverServices() first.',
      );
    }
    return c;
  }

  /// Reads a characteristic. / 读取特征。
  Future<Uint8List> read(String charUuid) async {
    _ensureConnected();
    final c = _resolve(charUuid);
    if (!c.properties.read) {
      throw StateError('Characteristic $charUuid is not readable.');
    }
    return Uint8List.fromList(await c.read());
  }

  /// Writes to a characteristic. / 写入特征。
  Future<bool> write(
    String charUuid,
    List<int> data, {
    bool withoutResponse = false,
  }) async {
    final c = _resolve(charUuid);
    if (!c.properties.write &&
        !(withoutResponse && c.properties.writeWithoutResponse)) {
      throw StateError('Characteristic $charUuid is not writable.');
    }
    try {
      await c.write(data, withoutResponse: withoutResponse);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Subscribes to a characteristic's notifications / indications.
  /// 订阅特征的通知 / 指示。
  ///
  /// Re-subscribing to an already-subscribed UUID returns the existing stream
  /// instead of leaking a second controller. / 对同一个已订阅 UUID 再次订阅会返回
  /// 既有流，而非泄漏第二个控制器。
  Stream<List<int>> subscribe(String charUuid) {
    _ensureConnected();
    final key = charUuid.toLowerCase();
    final existing = _subs[key];
    if (existing != null) return existing.controller.stream;
    final c = _resolve(charUuid);
    if (!c.properties.notify && !c.properties.indicate) {
      throw StateError(
        'Characteristic $charUuid does not support notify / indicate.',
      );
    }
    final controller = StreamController<List<int>>.broadcast();
    final sub = c.onValueReceived.listen(
      (v) => controller.add(v),
      onError: (e) => controller.addError(e),
      onDone: () => controller.close(),
    );
    // Surface an enable failure instead of silently yielding a dead stream.
    // / 开启失败要上报，而不是静默给一个死流。
    c.setNotifyValue(true).catchError((e) {
      controller.addError(e);
      return false;
    });
    controller.onCancel = () {
      // Cancel the *current* underlying listener: it is replaced on every
      // reconnect, so cancelling the captured first one would leak the new
      // subscription (which would then keep adding into a closed controller).
      // / 取消*当前*的底层监听：重连后它会被替换，若取消捕获的旧监听会泄漏新
      // 订阅（新订阅随后会持续向已关闭的 controller 投递数据）。
      final current = _subs.remove(key);
      unawaited(current?.dispose());
      final currentChar = _chars[key];
      if (currentChar != null) {
        currentChar.setNotifyValue(false).catchError((Object _) => false);
      }
    };
    _subs[key] = _Subscription(controller, sub);
    return controller.stream;
  }

  /// Re-points every active subscription at the freshly discovered
  /// characteristics and re-enables notify after a reconnect. /
  /// 在重连后，把每个活跃订阅重新指向刚发现的（有效）特征，并重新开启通知。
  Future<void> _rebindSubscriptions() async {
    if (_subs.isEmpty) return;
    // _chars is refreshed by the caller (connect path) before this runs. /
    // 调用方（连接路径）已在调用前刷新 _chars。
    for (final entry in _subs.entries) {
      final uuid = entry.key;
      final sub = entry.value;
      try {
        final c = _resolve(uuid);
        await sub.underlying.cancel();
        sub.underlying = c.onValueReceived.listen(
          (v) => sub.controller.add(v),
          onError: (e) => sub.controller.addError(e),
          onDone: () => sub.controller.close(),
        );
        await c.setNotifyValue(true).catchError((e) {
          sub.controller.addError(e);
          return false;
        });
      } catch (e) {
        sub.controller.addError(e);
      }
    }
  }

  void _teardownSubs() {
    for (final s in _subs.values) {
      s.dispose();
    }
    _subs.clear();
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _stateCtrl.add(value);
  }

  /// Disconnects, cancels reconnects, and tears down active subscriptions.
  /// 断开连接、取消重连，并拆除活跃订阅。
  ///
  /// The client can be [connect]ed again afterwards. Call [dispose] to release
  /// the connection-state stream as well. / 之后仍可再次 [connect]。若还要释放
  /// 连接状态流，请调用 [dispose]。
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _teardownSubs();
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      await _bt?.disconnect();
    } catch (_) {
      // Best effort. / 尽力而为。
    }
    _setConnected(false);
  }

  /// Releases every resource: active subscriptions, the connection, and the
  /// connection-state stream. Call when the client is no longer needed. /
  /// 释放全部资源：活跃订阅、连接，以及连接状态流。不再使用时调用。
  Future<void> dispose() async {
    await disconnect();
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
  }
}
