import 'package:flutter_rtc_link/flutter_rtc_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoGridController', () {
    late VideoGridController controller;

    setUp(() {
      controller = VideoGridController(maxVisible: 4);
    });

    tearDown(() {
      controller.dispose();
    });

    test('visible streams put the main first and cap at maxVisible', () {
      controller.setStreams(
        List<RemoteStream>.generate(6, (i) => RemoteStream(streamId: 'cam-$i')),
      );
      controller.setMain('cam-4');
      final visible = controller.value.visibleStreams;
      expect(visible.length, 4);
      expect(visible.first.streamId, 'cam-4');
      // Main is not duplicated. / 主画面不重复。
      expect(visible.where((s) => s.streamId == 'cam-4').length, 1);
    });

    test('speaker layout shows only the main stream', () {
      controller.setStreams(
        List<RemoteStream>.generate(3, (i) => RemoteStream(streamId: 'cam-$i')),
      );
      controller.setLayout(LayoutMode.speaker);
      expect(controller.value.thumbnailStreams, isEmpty);
      expect(controller.value.mainStream?.streamId, 'cam-0');
    });

    test('setMain ignores unknown stream ids', () {
      controller.setStreams(<RemoteStream>[const RemoteStream(streamId: 'a')]);
      controller.setMain('does-not-exist');
      expect(controller.value.mainStreamId, isNull);
    });

    test('global clarity clears per-stream overrides', () {
      controller.setStreams(<RemoteStream>[
        const RemoteStream(streamId: 'a'),
        const RemoteStream(streamId: 'b'),
      ]);
      controller.setStreamClarity('a', ClarityLevel.p540);
      expect(controller.value.clarityFor('a'), ClarityLevel.p540);
      expect(controller.value.clarityFor('b'), ClarityLevel.auto);
      controller.setGlobalClarity(ClarityLevel.p720);
      expect(controller.value.clarityFor('a'), ClarityLevel.p720);
      expect(controller.value.clarityFor('b'), ClarityLevel.p720);
    });

    test('removeStream clears the main selection when needed', () {
      controller.setStreams(<RemoteStream>[
        const RemoteStream(streamId: 'a'),
        const RemoteStream(streamId: 'b'),
      ]);
      controller.setMain('a');
      controller.removeStream('a');
      expect(controller.value.mainStreamId, isNull);
      expect(controller.value.mainStream?.streamId, 'b');
    });

    test('stale clarity overrides are dropped with their stream', () {
      controller.setStreams(<RemoteStream>[
        const RemoteStream(streamId: 'a'),
        const RemoteStream(streamId: 'b'),
      ]);
      controller.setStreamClarity('b', ClarityLevel.p540);
      expect(controller.value.clarityOverrides.length, 1);
      controller.removeStream('b');
      expect(controller.value.clarityOverrides, isEmpty);
      expect(controller.value.clarityFor('b'), ClarityLevel.auto);
    });

    test('applyClarity invokes the callback for visible streams', () async {
      controller.setStreams(<RemoteStream>[
        const RemoteStream(streamId: 'a'),
        const RemoteStream(streamId: 'b'),
      ]);
      controller.setStreamClarity('b', ClarityLevel.p1080);
      final applied = <String, ClarityLevel>{};
      await controller.applyClarity((streamId, level) async {
        applied[streamId] = level;
      });
      expect(applied, <String, ClarityLevel>{
        'a': ClarityLevel.auto,
        'b': ClarityLevel.p1080,
      });
    });
  });
}
