import 'package:flutter_rtc_link/rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSimulcastEncodings', () {
    test('builds three layers with stable rids', () {
      final encodings = buildSimulcastEncodings(ClarityLevel.p1080);
      expect(encodings.length, 3);
      expect(encodings.map((e) => e.rid), <String?>['f', 'h', 'q']);
    });

    test('caps the top layer for lower clarity levels', () {
      final encodings = buildSimulcastEncodings(ClarityLevel.p360);
      expect(encodings.length, 3);
      expect(encodings.first.active, isFalse, reason: 'full layer inactive');
      expect(encodings[1].active, isFalse, reason: 'half layer inactive');
      expect(encodings.last.active, isTrue, reason: 'quarter layer active');
    });

    test('all layers are active for p720 and above', () {
      for (final level in <ClarityLevel>[
        ClarityLevel.p720,
        ClarityLevel.p1080,
      ]) {
        final encodings = buildSimulcastEncodings(level);
        expect(encodings.every((e) => e.active), isTrue, reason: '$level');
      }
    });
  });

  group('applyClarityToEncodings', () {
    test('activates layers up to the requested level', () {
      final encodings = buildSimulcastEncodings(ClarityLevel.p1080);
      applyClarityToEncodings(encodings, ClarityLevel.p540);
      expect(encodings.last.active, isTrue);
      expect(encodings[1].active, isTrue);
      expect(encodings.first.active, isFalse);
    });

    test('auto keeps every layer active', () {
      final encodings = buildSimulcastEncodings(ClarityLevel.p1080);
      applyClarityToEncodings(encodings, ClarityLevel.auto);
      expect(encodings.every((e) => e.active), isTrue);
    });
  });
}
