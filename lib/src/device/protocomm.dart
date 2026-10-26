import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/rtc_events.dart';

/// Transport for protocomm endpoints (BLE GATT, console, HTTP).
/// protocomm 端点的传输层（BLE GATT、console、HTTP）。
abstract class ProtocommTransport {
  /// Connects to the device. / 连接设备。
  Future<bool> connect();

  /// Disconnects from the device. / 断开设备。
  Future<bool> disconnect();

  /// Whether the transport is connected. / 传输是否已连接。
  Future<bool> checkConnect();

  /// Sends [data] to [endpoint] and returns the response bytes.
  /// 向 [endpoint] 发送 [data] 并返回响应字节。
  Future<Uint8List> sendReceive(String endpoint, Uint8List data);
}

/// Minimal protobuf wire writer (only what protocomm needs).
/// 最小 protobuf 线格式写入器（仅 protocomm 所需）。
class PbWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Writes a varint field. / 写入 varint 字段。
  void varint(int field, int value) {
    _tag(field, 0);
    _varint(value);
  }

  /// Writes a length-delimited field. / 写入长度分隔字段。
  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _varint(value.length);
    _builder.add(value);
  }

  void _tag(int field, int wireType) => _varint((field << 3) | wireType);

  void _varint(int value) {
    // Protobuf varints are unsigned; a negative value would either loop
    // forever or blow up in addByte. Fail loudly instead. /
    // protobuf varint 是无符号的；负值会死循环或让 addByte 崩溃，因此显式报错。
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'value',
        'protobuf varint cannot be negative',
      );
    }
    var v = value;
    while (v >= 0x80) {
      _builder.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _builder.addByte(v);
  }

  /// Takes the encoded bytes. / 取出编码后的字节。
  Uint8List takeBytes() => _builder.takeBytes();
}

/// Minimal protobuf wire reader (only what protocomm needs).
/// 最小 protobuf 线格式读取器（仅 protocomm 所需）。
class PbReader {
  PbReader(this._bytes) : _offset = 0;

  final Uint8List _bytes;
  int _offset;

  /// Whether more fields remain. / 是否还有后续字段。
  bool get hasMore => _offset < _bytes.length;

  /// Reads the next field as (fieldNumber, value, wireType). / 读取下一个字段为 (字段号, 值, 线类型)。
  ({int field, int wireType, Object? value}) next() {
    final tag = _readVarint();
    final field = tag >> 3;
    final wireType = tag & 0x07;
    if (wireType == 0) {
      return (field: field, wireType: wireType, value: _readVarint());
    }
    if (wireType == 2) {
      final length = _readVarint();
      // Guard against a length that overruns the buffer. /
      // 防止长度超出缓冲区。
      if (length < 0 || _offset + length > _bytes.length) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'Truncated protobuf field (length $length).',
        );
      }
      final value = _bytes.sublist(_offset, _offset + length);
      _offset += length;
      return (field: field, wireType: wireType, value: value);
    }
    throw RtcException(
      code: RtcErrorCodes.signalingFailed,
      message: 'Unsupported protobuf wire type $wireType.',
    );
  }

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      // Bounds check: a truncated response must raise a typed error, not a
      // RangeError from the raw list access. /
      // 边界检查：响应被截断时应抛类型化错误，而不是列表访问的 RangeError。
      if (_offset >= _bytes.length) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'Truncated protobuf varint.',
        );
      }
      final byte = _bytes[_offset++];
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
      if (shift > 63) {
        throw RtcException(
          code: RtcErrorCodes.signalingFailed,
          message: 'Protobuf varint is too long.',
        );
      }
    }
  }

  /// Finds the bytes value of a field, or null. / 查找某字段的 bytes 值，无则 null。
  Uint8List? bytesField(int field) {
    final reader = PbReader(_bytes);
    while (reader.hasMore) {
      try {
        final next = reader.next();
        if (next.field == field && next.value is Uint8List) {
          return next.value! as Uint8List;
        }
      } catch (_) {
        // A malformed field aborts the scan instead of crashing the caller. /
        // 畸形字段中止扫描，而不是让调用方崩溃。
        return null;
      }
    }
    return null;
  }

  /// Finds the varint value of a field, or 0. / 查找某字段的 varint 值，无则 0。
  int varintField(int field) {
    final reader = PbReader(_bytes);
    while (reader.hasMore) {
      try {
        final next = reader.next();
        if (next.field == field && next.value is int) return next.value! as int;
      } catch (_) {
        // A malformed field aborts the scan instead of crashing the caller. /
        // 畸形字段中止扫描，而不是让调用方崩溃。
        return 0;
      }
    }
    return 0;
  }
}

/// Result of a provisioning connection status query. / 配网连接状态查询结果。
enum ProvisionConnectionState {
  /// Connected to the Wi-Fi network. / 已连接到 Wi-Fi 网络。
  connected,

  /// Connecting. / 连接中。
  connecting,

  /// Disconnected. / 已断开。
  disconnected,

  /// Connection failed: wrong password. / 连接失败：密码错误。
  authError,

  /// Connection failed: AP not found. / 连接失败：找不到 AP。
  networkNotFound,

  /// Connection failed for another reason. / 连接失败（其它原因）。
  connectionFailed,
}

/// Provisioning connection status. / 配网连接状态。
class ProvisionStatus {
  const ProvisionStatus({
    required this.state,
    this.deviceIp,
    this.failedReason,
  });

  final ProvisionConnectionState state;
  final String? deviceIp;
  final String? failedReason;
}

/// protocomm Security1 (Curve25519 + AES-256-CTR) session.
/// protocomm Security1（Curve25519 + AES-256-CTR）会话。
///
/// Implemented in pure Dart on top of `cryptography` — no native plugins and
/// no `protobuf` dependency, which keeps the plugin's transitive dependency
/// tree free of version conflicts.
/// 基于 `cryptography` 纯 Dart 实现——无原生插件、无 `protobuf` 依赖，
/// 使插件的传递依赖树免于版本冲突。
class ProtocommSecurity1 {
  ProtocommSecurity1({
    this.pop,
    Uint8List Function(Uint8List deviceRandom)? nonceBuilder,
  }) : _nonceBuilder = nonceBuilder ?? _defaultNonce;

  /// Proof of Possession (device auth); null for the no-auth scheme.
  /// 所有权证明（设备鉴权）；无鉴权方案传 null。
  final String? pop;

  final Uint8List Function(Uint8List deviceRandom) _nonceBuilder;

  static final X25519 _x25519 = X25519();
  static final Sha256 _sha256 = Sha256();
  static final AesCtr _aes = AesCtr.with256bits(
    macAlgorithm: MacAlgorithm.empty,
  );

  SimpleKeyPair? _clientKey;
  Uint8List? _sharedKey;
  Uint8List? _deviceRandom;
  Uint8List? _nonce;
  int _offset = 0;
  int _state = 0; // 0=request1, 1=response1Request2, 2=response2, 3=finish

  /// Whether the session is established. / 会话是否已建立。
  bool get isEstablished => _state == 3;

  /// Encrypts / decrypts (CTR is symmetric). / 加密 / 解密（CTR 对称）。
  Future<Uint8List> transform(Uint8List data) async {
    final key = _sharedKey;
    final nonce = _nonce;
    if (key == null || nonce == null) {
      throw StateError('protocomm session is not established');
    }
    // The device keeps ONE continuous CTR keystream: every message continues
    // exactly where the previous one stopped — including the intra-block
    // offset. Advancing the counter by whole blocks only (as this used to do)
    // silently drops the remainder of a partial block and misaligns every
    // later message, because AesCtr always starts at byte 0 of a block.
    // 设备端维持一条连续的 CTR keystream：每条消息都精确接着上一条继续——包括
    // 块内偏移。只按整块推进计数器（原实现）会静默丢弃不满一块的余数，而
    // AesCtr 总是从块的第 0 字节开始，于是之后每条消息都错位。
    final skip = _offset % 16;
    final counter = _counterFor(_offset ~/ 16);
    late final Uint8List cipherText;
    if (skip == 0) {
      final secretBox = await _aes.encrypt(
        data,
        secretKey: SecretKey(key),
        nonce: counter,
      );
      cipherText = Uint8List.fromList(secretBox.cipherText);
    } else {
      // Prepend `skip` placeholder bytes so the keystream lines up with the
      // intra-block offset, then drop them again. /
      // 前置 skip 个占位字节使 keystream 对齐块内偏移，之后再丢弃。
      final padded = Uint8List(skip + data.length);
      padded.setRange(skip, padded.length, data);
      final secretBox = await _aes.encrypt(
        padded,
        secretKey: SecretKey(key),
        nonce: counter,
      );
      cipherText = Uint8List.fromList(secretBox.cipherText.sublist(skip));
    }
    _offset += data.length;
    return cipherText;
  }

  /// Builds the 16-byte counter block for [blockIndex] blocks past the base
  /// nonce. / 构造相对基础 nonce 前进 [blockIndex] 块的 16 字节计数器块。
  Uint8List _counterFor(int blockIndex) {
    final counter = Uint8List.fromList(_nonce!);
    if (blockIndex == 0) return counter;
    // Advance the 16-byte counter block (big-endian carry propagation).
    // 推进 16 字节计数器块（大端进位传递）。
    var carry = blockIndex;
    for (var i = counter.length - 1; i >= 0 && carry > 0; i--) {
      final sum = counter[i] + carry;
      counter[i] = sum & 0xFF;
      carry = sum >> 8;
    }
    return counter;
  }

  /// Builds the next session request, or null when the handshake is done.
  /// 构造下一条会话请求；握手完成时返回 null。
  Future<Uint8List?> securitySession(Uint8List? responseData) async {
    switch (_state) {
      case 0:
        _state = 1;
        return _setup0Request();
      case 1:
        _state = 2;
        await _setup0Response(responseData!);
        return _setup1Request();
      case 2:
        _state = 3;
        await _setup1Response(responseData!);
        return null;
      default:
        return null;
    }
  }

  Future<Uint8List> _setup0Request() async {
    _clientKey = await _x25519.newKeyPair();
    final publicKey = await _clientKey!.extractPublicKey();
    final sc0 = PbWriter()..bytes(1, publicKey.bytes);
    final sec1 = PbWriter()..bytes(20, sc0.takeBytes());
    final session = PbWriter()
      ..varint(2, 1) // SecScheme1
      ..bytes(11, sec1.takeBytes());
    return session.takeBytes();
  }

  Future<void> _setup0Response(Uint8List response) async {
    final session = PbReader(response);
    if (session.varintField(2) != 1) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device requested an unsupported protocomm security scheme.',
      );
    }
    final sec1Payload = session.bytesField(11);
    if (sec1Payload == null) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device sent no sec1 payload.',
      );
    }
    final sr0 = PbReader(sec1Payload).bytesField(21);
    if (sr0 == null) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device sent no SessionResp0.',
      );
    }
    final resp0 = PbReader(sr0);
    final status = resp0.varintField(1);
    if (status != 0) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device rejected the session (status $status).',
      );
    }
    final devicePublicKey = resp0.bytesField(2);
    final deviceRandom = resp0.bytesField(3);
    if (devicePublicKey == null || deviceRandom == null) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device sent an incomplete SessionResp0.',
      );
    }
    _deviceRandom = deviceRandom;
    final remotePublicKey = SimplePublicKey(
      devicePublicKey,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _clientKey!,
      remotePublicKey: remotePublicKey,
    );
    var sharedKey = Uint8List.fromList(await sharedSecret.extractBytes());
    final pop = this.pop;
    if (pop != null && pop.isNotEmpty) {
      final hash = await _sha256.hash(utf8.encode(pop));
      sharedKey = _xor(sharedKey, Uint8List.fromList(hash.bytes));
    }
    _sharedKey = sharedKey;
    _nonce = _nonceBuilder(_deviceRandom!);
    _offset = 0;
  }

  Future<Uint8List> _setup1Request() async {
    final clientPublicKey = await _clientKey!.extractPublicKey();
    final clientVerify = await transform(
      Uint8List.fromList(clientPublicKey.bytes),
    );
    final sc1 = PbWriter()..bytes(1, clientVerify);
    final sec1 = PbWriter()
      ..varint(1, 2) // Session_Command1
      ..bytes(22, sc1.takeBytes());
    final session = PbWriter()
      ..varint(2, 1)
      ..bytes(11, sec1.takeBytes());
    return session.takeBytes();
  }

  Future<void> _setup1Response(Uint8List response) async {
    // Never fail open: a missing payload must NOT skip device authentication,
    // otherwise a device (or MITM) that omits SessionResp1 gets a "secure"
    // session for free. / 绝不能失败开放：缺少载荷也不能跳过设备鉴权，否则
    // 省略 SessionResp1 的设备（或中间人）就能白拿一个"安全"会话。
    final sec1Payload = PbReader(response).bytesField(11);
    if (sec1Payload == null) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device sent no sec1 payload in SessionResp1.',
      );
    }
    final sr1 = PbReader(sec1Payload).bytesField(22);
    if (sr1 == null) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'Device sent no SessionResp1.',
      );
    }
    final deviceVerify = PbReader(sr1).bytesField(2);
    if (deviceVerify == null) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message:
            'Device sent no verification token (wrong PoP or possible MITM).',
      );
    }
    final decrypted = await transform(deviceVerify);
    final clientPublicKey = await _clientKey!.extractPublicKey();
    if (!_equals(decrypted, clientPublicKey.bytes)) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'protocomm device verify mismatch (wrong PoP or MITM).',
      );
    }
  }

  static Uint8List _defaultNonce(Uint8List deviceRandom) {
    // AES-CTR needs a 16-byte counter block; ESP-IDF seeds it from the
    // device random. Firmware variants exist, so the derivation is
    // overridable via the constructor.
    // AES-CTR 需要 16 字节计数器块；ESP-IDF 用设备随机数作为种子。
    // 固件存在变体，因此该推导可通过构造函数覆盖。
    if (deviceRandom.length >= 16) {
      return Uint8List.fromList(deviceRandom.sublist(0, 16));
    }
    final padded = Uint8List(16);
    padded.setRange(0, deviceRandom.length, deviceRandom);
    return padded;
  }

  static Uint8List _xor(Uint8List a, Uint8List b) {
    final out = Uint8List(max(a.length, b.length));
    for (var i = 0; i < out.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      out[i] = x ^ y;
    }
    return out;
  }

  static bool _equals(Uint8List a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// ESP32 protocomm provisioning client (Wi-Fi station config).
/// ESP32 protocomm 配网客户端（Wi-Fi station 配置）。
class EspProtocomm {
  EspProtocomm({required this.transport, required this.security});

  final ProtocommTransport transport;
  final ProtocommSecurity1 security;

  /// Establishes the secure session (3 round-trips). / 建立安全会话（三次往返）。
  Future<bool> establishSession() async {
    try {
      Uint8List? response;
      while (await transport.checkConnect()) {
        final request = await security.securitySession(response);
        if (request == null) return true;
        final received = await transport.sendReceive('prov-session', request);
        if (received.isEmpty) {
          throw RtcException(
            code: RtcErrorCodes.signalingFailed,
            message: 'protocomm session endpoint returned an empty response.',
          );
        }
        response = received;
      }
      return false;
    } on RtcException {
      rethrow;
    } catch (e) {
      throw RtcException(
        code: RtcErrorCodes.signalingFailed,
        message: 'protocomm session failed.',
        cause: e,
      );
    }
  }

  /// Sends the Wi-Fi credentials. / 下发 Wi-Fi 凭据。
  Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
    String? bssid,
  }) async {
    final cmdSetConfig = PbWriter()
      ..bytes(1, utf8.encode(ssid))
      ..bytes(2, utf8.encode(password));
    if (bssid != null) {
      cmdSetConfig.bytes(3, _encodeBssid(bssid));
    }
    final payload = PbWriter()
      ..varint(1, 2) // TypeCmdSetConfig
      ..bytes(12, cmdSetConfig.takeBytes());
    final response = await _exchange('prov-config', payload.takeBytes());
    final respSetConfig = PbReader(response).bytesField(13);
    final status = respSetConfig == null
        ? -1
        : PbReader(respSetConfig).varintField(1);
    return status == 0;
  }

  /// Applies the credentials (device joins the network). / 应用凭据（设备入网）。
  Future<bool> applyWifiConfig() async {
    final payload = PbWriter()
      ..varint(1, 4) // TypeCmdApplyConfig
      ..bytes(14, Uint8List(0));
    final response = await _exchange('prov-config', payload.takeBytes());
    final respApply = PbReader(response).bytesField(15);
    final status = respApply == null ? -1 : PbReader(respApply).varintField(1);
    return status == 0;
  }

  /// Reads the connection status from the device. / 读取设备的连接状态。
  Future<ProvisionStatus> getStatus() async {
    final payload = PbWriter()
      ..varint(1, 0) // TypeCmdGetStatus
      ..bytes(10, Uint8List(0));
    final response = await _exchange('prov-config', payload.takeBytes());
    final respGetStatus = PbReader(response).bytesField(11);
    if (respGetStatus == null) {
      return const ProvisionStatus(
        state: ProvisionConnectionState.connectionFailed,
      );
    }
    final reader = PbReader(respGetStatus);
    final staState = reader.varintField(2);
    switch (staState) {
      case 0:
        final connected = reader.bytesField(11);
        String? ip;
        if (connected != null) {
          final bytes = PbReader(connected).bytesField(1);
          if (bytes != null && bytes.length == 4) {
            ip = bytes.join('.');
          }
        }
        return ProvisionStatus(
          state: ProvisionConnectionState.connected,
          deviceIp: ip,
        );
      case 1:
        return const ProvisionStatus(
          state: ProvisionConnectionState.connecting,
        );
      case 2:
        return const ProvisionStatus(
          state: ProvisionConnectionState.disconnected,
        );
      case 3:
        final failReason = reader.varintField(10);
        return ProvisionStatus(
          state: failReason == 0
              ? ProvisionConnectionState.authError
              : ProvisionConnectionState.networkNotFound,
        );
      default:
        return const ProvisionStatus(
          state: ProvisionConnectionState.connectionFailed,
        );
    }
  }

  Future<Uint8List> _exchange(String endpoint, Uint8List payload) async {
    final encrypted = await security.transform(payload);
    final response = await transport.sendReceive(endpoint, encrypted);
    if (response.isEmpty) return Uint8List(0);
    return security.transform(response);
  }

  static final RegExp _bssidFormat = RegExp(
    r'^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$',
  );

  static List<int> _encodeBssid(String hexBssid) {
    if (!_bssidFormat.hasMatch(hexBssid)) {
      throw FormatException(
        'Invalid BSSID "$hexBssid": expected 6 colon-separated hex byte pairs.',
        hexBssid,
      );
    }
    return hexBssid.split(':').map((e) => int.parse(e, radix: 16)).toList();
  }

  /// Disposes the client (disconnects the transport). / 释放客户端（断开传输）。
  Future<void> dispose() async {
    await transport.disconnect();
  }
}
