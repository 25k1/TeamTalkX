@Tags(['native'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/silero_vad.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/opus_decoder.dart';
import 'package:teamtalkx/src/audio/opus_encoder.dart';
import 'package:teamtalkx/src/audio/speex_codec.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

Uint8List _noise(math.Random random, int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) random.nextInt(256)]);

Int16List _tone(int samples, int index) => Int16List.fromList([
  for (var i = 0; i < samples; i++)
    (math.sin(2 * math.pi * 440 * (index * samples + i) / 48000) * 9000)
        .round(),
]);

void main() {
  group('network data the decoders must survive', skip: _skip, () {
    test('Opus: random, truncated and bit-flipped packets', () {
      final random = math.Random(7);
      final encoder = OpusFrameEncoder(sampleRate: 48000, channels: 2);
      final decoder = OpusFrameDecoder(sampleRate: 48000, channels: 2);
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);
      for (var i = 0; i < 2000; i++) {
        final out = decoder.decode(_noise(random, 1 + random.nextInt(1500)));
        expect(out.length, lessThanOrEqualTo(5760 * 2));
      }
      for (var i = 0; i < 200; i++) {
        final packet = encoder.encode(_tone(960 * 2, i));
        decoder.decode(Uint8List.sublistView(packet, 0, i % packet.length));
        final flipped = Uint8List.fromList(packet);
        flipped[random.nextInt(flipped.length)] ^= 1 << random.nextInt(8);
        decoder.decode(flipped);
        decoder.decode(packet, maxSamplesPerChannel: 120);
      }
      expect(decoder.decodeLost(), hasLength(960 * 2));
    });

    test('Opus: recovery from random and corrupted next packets', () {
      final random = math.Random(5);
      final encoder = OpusFrameEncoder(
        sampleRate: 48000,
        channels: 1,
        fec: true,
        lossPercent: 10,
        dredMs: 100,
      );
      final decoder = OpusFrameDecoder(sampleRate: 48000, channels: 2)
        ..setQuality(complexity: 7, bandwidthExtension: true);
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);
      for (var i = 0; i < 300; i++) {
        final packet = Uint8List.fromList(encoder.encode(_tone(960, i)));
        final next = switch (i % 3) {
          0 => _noise(random, 1 + random.nextInt(1500)),
          1 => (Uint8List.fromList(
            packet,
          )..[random.nextInt(packet.length)] ^= 1 << random.nextInt(8)),
          _ => packet,
        };
        final ahead = 1 + random.nextInt(60);
        final out = decoder.recover(
          next,
          offset: ahead * 960,
          samplesPerChannel: 960,
        );
        expect(out, hasLength(960 * 2));
      }
    });

    test('Speex: random and truncated frames in every band', () {
      final random = math.Random(11);
      for (final band in [0, 1, 2]) {
        final encoder = SpeexFrameEncoder(bandMode: band, quality: 8);
        final decoder = SpeexFrameDecoder(bandMode: band);
        addTearDown(encoder.dispose);
        addTearDown(decoder.dispose);
        final samples = speexSampleRate(band) ~/ 50;
        for (var i = 0; i < 2000; i++) {
          try {
            final out = decoder.decode(_noise(random, random.nextInt(2048)));
            expect(out, hasLength(samples));
          } on FormatException {
            continue;
          }
        }
        for (var i = 0; i < 100; i++) {
          final frame = encoder.encode(
            Int16List.sublistView(_tone(samples, i), 0, samples),
          );
          try {
            decoder.decode(Uint8List.sublistView(frame, 0, i % frame.length));
          } on FormatException {
            continue;
          }
        }
        expect(decoder.decode(null), hasLength(samples));
      }
    });

    test('Silero: odd piece sizes and extreme samples', () {
      final vad = SileroVad(
        File('assets/vad/silero_vad_v6_2.bin').readAsBytesSync(),
      );
      addTearDown(vad.dispose);
      final random = math.Random(3);
      var chunks = 0;
      var fed = 0;
      for (var i = 0; i < 400; i++) {
        final length = random.nextInt(1500);
        final pcm = Int16List.fromList([
          for (var j = 0; j < length; j++) random.nextBool() ? -32768 : 32767,
        ]);
        fed += length;
        final probs = vad.feed(pcm);
        chunks += probs.length;
        expect(probs.every((p) => p >= 0 && p <= 1), isTrue);
      }
      expect(chunks, fed ~/ SileroVad.chunkSize);
    });
  });
}
