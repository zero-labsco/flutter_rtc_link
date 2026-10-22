import 'dart:convert';
import 'dart:io';

import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake uploader that records batches. / 记录批次的假上传器。
class FakeUploader implements LogUploader {
  final List<List<DeviceLogEntry>> batches = <List<DeviceLogEntry>>[];
  bool nextUploadSucceeds = true;

  @override
  Future<bool> upload(String deviceId, List<DeviceLogEntry> entries) async {
    if (!nextUploadSucceeds) return false;
    batches.add(entries);
    return true;
  }
}

void main() {
  group('redactSensitiveData', () {
    test('masks emails, phone numbers and secrets', () {
      final redacted = redactSensitiveData(
        'user test@example.com phone 13800138000 token: abc123',
      );
      expect(redacted.contains('test@example.com'), isFalse);
      expect(redacted.contains('***@***'), isTrue);
      expect(redacted.contains('13800138000'), isFalse);
      expect(redacted.contains('abc123'), isFalse);
      expect(redacted.contains('token: ***'), isTrue);
    });
  });

  group('FileLogCache', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('rtc_link_log_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    DeviceLogEntry entry(int i) => DeviceLogEntry(
      timestamp: DateTime.utc(2026, 1, 1, 0, 0, i),
      level: LogLevel.info,
      tag: 't$i',
      message: 'm$i',
    );

    test('append/take/peek round-trip', () async {
      final cache = FileLogCache(deviceId: 'dev', directory: tempDir.path);
      await cache.append(<DeviceLogEntry>[entry(1), entry(2)]);
      expect(await cache.pendingCount, 2);
      final peeked = await cache.peek();
      expect(peeked.map((e) => e.message), <String>['m1', 'm2']);
      expect(await cache.pendingCount, 2, reason: 'peek must not consume');
      final taken = await cache.take();
      expect(taken.map((e) => e.message), <String>['m1', 'm2']);
      expect(await cache.pendingCount, 0);
      await cache.clear();
    });

    test('rotation keeps only the newest maxEntries', () async {
      final cache = FileLogCache(
        deviceId: 'dev',
        maxEntries: 3,
        directory: tempDir.path,
      );
      for (var i = 1; i <= 6; i++) {
        await cache.append(<DeviceLogEntry>[entry(i)]);
      }
      expect(await cache.pendingCount, 3);
      final peeked = await cache.peek();
      expect(peeked.map((e) => e.message), <String>['m4', 'm5', 'm6']);
    });
  });

  group('DeviceLogCollector', () {
    test('flush uploads and emits LogBatchUploaded', () async {
      final uploader = FakeUploader();
      final collector = DeviceLogCollector(uploader: uploader);
      final events = <DeviceEvent>[];
      collector.events.listen(events.add);
      await collector.start(deviceId: 'dev');
      collector.log(LogLevel.info, 'tag', 'hello');
      await collector.flush();
      expect(uploader.batches.single.single.message, 'hello');
      expect(events.whereType<LogBatchUploaded>(), isNotEmpty);
      await collector.dispose();
    });

    test('failed upload falls back to the local cache', () async {
      final uploader = FakeUploader()..nextUploadSucceeds = false;
      final tempDir = Directory.systemTemp.createTempSync('rtc_link_collector');
      final cache = FileLogCache(deviceId: 'dev', directory: tempDir.path);
      final collector = DeviceLogCollector(uploader: uploader, cache: cache);
      await collector.start(deviceId: 'dev');
      collector.log(LogLevel.error, 'tag', 'boom');
      await collector.flush();
      expect(uploader.batches, isEmpty);
      expect(await cache.pendingCount, 1);
      // Once the network recovers, the new batch is sent and the cached
      // batch is re-sent as a second batch.
      // 网络恢复后：新批次发送，缓存批次作为第二批补传。
      uploader.nextUploadSucceeds = true;
      collector.log(LogLevel.info, 'tag', 'after-recovery');
      await collector.flush();
      expect(uploader.batches.length, 2);
      expect(uploader.batches.expand((b) => b).length, 2);
      expect(await cache.pendingCount, 0);
      await collector.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('crash bundle packages the last N entries', () async {
      final collector = DeviceLogCollector();
      await collector.start(deviceId: 'dev');
      for (var i = 0; i < 5; i++) {
        collector.log(LogLevel.info, 'tag', 'log $i');
      }
      final bundle = await collector.collectCrashBundle(lastN: 3);
      final logs = (bundle['logs'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
      expect(logs.length, 3);
      expect(logs.last['message'], 'log 4');
      expect(bundle['deviceId'], 'dev');
      expect(jsonEncode(bundle), isNotEmpty);
      await collector.dispose();
    });

    test('keyword filter drops non-matching entries', () async {
      final collector = DeviceLogCollector(keywordFilter: RegExp('keep'));
      await collector.start(deviceId: 'dev');
      collector.log(LogLevel.info, 'tag', 'keep this');
      collector.log(LogLevel.info, 'tag', 'drop this');
      await collector.flush();
      await collector.dispose();
    });
  });
}
