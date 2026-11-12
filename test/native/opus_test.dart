@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/opus_decoder.dart';
import 'package:teamtalkx/src/audio/opus_encoder.dart';

void main() {
  test(
    'Opus round-trips a 20 ms frame',
    skip: nativeLibraryOverride == ''
        ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
        : null,
    () {
      final encoder = OpusFrameEncoder(sampleRate: 48000, channels: 1);
      final decoder = OpusFrameDecoder(sampleRate: 48000, channels: 1);
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);
      final pcm = Int16List.fromList([
        for (var i = 0; i < 960; i++)
          (math.sin(2 * math.pi * 440 * i / 48000) * 10000).round(),
      ]);

      final packet = encoder.encode(pcm);
      expect(packet, isNotEmpty);
      expect(decoder.decode(packet), hasLength(960));
    },
  );
}
