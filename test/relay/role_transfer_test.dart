import 'dart:convert';

import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoleTransferNotice', () {
    test('round-trips through JSON', () {
      const notice = RoleTransferNotice(
        action: 'promote',
        targetIdentity: 'user-7788',
        role: 'coHost',
      );
      final decoded = RoleTransferNotice.tryDecode(
        utf8.encode(jsonEncode(notice.toJson())),
      );
      expect(decoded, isNotNull);
      expect(decoded!.action, 'promote');
      expect(decoded.targetIdentity, 'user-7788');
      expect(decoded.role, 'coHost');
    });

    test('returns null for malformed payloads', () {
      expect(RoleTransferNotice.tryDecode(utf8.encode('not-json')), isNull);
      expect(RoleTransferNotice.tryDecode(utf8.encode('[1,2,3]')), isNull);
      expect(RoleTransferNotice.tryDecode(utf8.encode('"a string"')), isNull);
    });
  });

  group('WhipWhepClient URL building', () {
    test('stream id is appended as a query parameter', () {
      final uri = WhipWhepClient.resolveStreamUri(
        endpoint: 'https://srs.example.com/rtc/v1/whip/?app=live',
        streamId: 'cam-01',
      );
      expect(uri.queryParameters['app'], 'live');
      expect(uri.queryParameters['stream'], 'cam-01');
    });

    test('an existing stream parameter is not duplicated', () {
      final uri = WhipWhepClient.resolveStreamUri(
        endpoint: 'https://srs.example.com/rtc/v1/whip/?app=live&stream=other',
        streamId: 'cam-01',
      );
      expect(uri.queryParametersAll['stream'], <String>['other']);
    });

    test('endpoints without a query string still work', () {
      final uri = WhipWhepClient.resolveStreamUri(
        endpoint: 'https://zlm.example.com/index/api/whip',
        streamId: 'cam-01',
      );
      expect(uri.queryParameters['stream'], 'cam-01');
    });
  });
}
