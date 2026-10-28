import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_rtc_link/flutter_rtc_link_device.dart';
import 'package:ndef_record/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart' show NdefAndroid;
import 'package:nfc_manager/nfc_manager_ios.dart' show NdefIos;

/// [NfcTagBackend] implementation built on `nfc_manager`.
/// 基于 `nfc_manager` 实现的 [NfcTagBackend]。
///
/// The plugin ships the abstraction only — wiring the hardware stack is the
/// app's decision, and this is where the demo does it.
/// 插件只提供抽象——接硬件技术栈由应用决定，本文件就是演示应用接线的地方。
class NfcManagerTagBackend implements NfcTagBackend {
  const NfcManagerTagBackend();

  @override
  Future<String?> readText({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<String?>();
    Timer? timeoutTimer;
    await NfcManager.instance.startSession(
      pollingOptions: const <NfcPollingOption>{
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (tag) async {
        final message = await _readNdefMessage(tag);
        final text = message == null ? null : _firstText(message);
        if (!completer.isCompleted) completer.complete(text);
        await NfcManager.instance.stopSession();
      },
    );
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
      NfcManager.instance.stopSession();
    });
    final result = await completer.future;
    timeoutTimer.cancel();
    return result;
  }

  @override
  Future<bool> writeText(
    String text, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<bool>();
    Timer? timeoutTimer;
    await NfcManager.instance.startSession(
      pollingOptions: const <NfcPollingOption>{
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (tag) async {
        final ok = await _writeNdefMessage(tag, _textMessage(text));
        if (!completer.isCompleted) completer.complete(ok);
        await NfcManager.instance.stopSession();
      },
    );
    timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
      NfcManager.instance.stopSession();
    });
    final result = await completer.future;
    timeoutTimer.cancel();
    return result;
  }

  static Future<NdefMessage?> _readNdefMessage(NfcTag tag) async {
    final android = NdefAndroid.from(tag);
    if (android != null) return android.getNdefMessage();
    final ios = NdefIos.from(tag);
    if (ios != null) return ios.readNdef();
    return null;
  }

  static Future<bool> _writeNdefMessage(NfcTag tag, NdefMessage message) async {
    try {
      final android = NdefAndroid.from(tag);
      if (android != null) {
        await android.writeNdefMessage(message);
        return true;
      }
      final ios = NdefIos.from(tag);
      if (ios != null) {
        await ios.writeNdef(message);
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static NdefMessage _textMessage(String text) {
    return NdefMessage(
      records: <NdefRecord>[
        NdefRecord(
          typeNameFormat: TypeNameFormat.wellKnown,
          type: Uint8List.fromList(utf8.encode('T')),
          identifier: Uint8List(0),
          payload: _textPayload(text),
        ),
      ],
    );
  }

  static String? _firstText(NdefMessage message) {
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.wellKnown) continue;
      if (utf8.decode(record.type) != 'T') continue;
      return _decodeTextPayload(record.payload);
    }
    return null;
  }

  /// Builds an NDEF text-record payload (status byte + language + text).
  /// 构造 NDEF 文本记录载荷（状态字节 + 语言 + 文本）。
  static Uint8List _textPayload(String text) {
    final language = utf8.encode('en');
    final body = BytesBuilder()
      ..addByte(0x02) // UTF-8, language length 3 bits
      ..add(language)
      ..add(utf8.encode(text));
    return body.toBytes();
  }

  static String _decodeTextPayload(Uint8List payload) {
    if (payload.isEmpty) return '';
    final status = payload[0];
    final languageLength = status & 0x3F;
    final isUtf8 = (status & 0x80) == 0;
    final textBytes = payload.sublist(1 + languageLength);
    return isUtf8 ? utf8.decode(textBytes) : latin1.decode(textBytes);
  }
}
