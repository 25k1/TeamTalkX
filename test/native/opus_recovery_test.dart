@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_packetizer.dart';
import 'package:teamtalkx/src/audio/codec_config.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/opus_decoder.dart';
import 'package:teamtalkx/src/audio/opus_encoder.dart';
import 'package:teamtalkx/src/domain/voice_quality.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

const _rate = 48000;
const _frame = 960;

Int16List _speechLike(int frames) {
  final random = math.Random(1);
  final out = Int16List(frames * _frame);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / _rate;
    final syllable = 0.5 - 0.5 * math.cos(2 * math.pi * 4 * t);
    final voiced = math.sin(2 * math.pi * 0.7 * t) > -0.6;
    final pitch = 120 + 60 * math.sin(2 * math.pi * 0.3 * t);
    phase += 2 * math.pi * pitch / _rate;
    var s = 0.0;
    if (voiced) {
      for (var h = 1; h <= 30; h++) {
        final f = h * pitch;
        final formants =
            math.exp(-math.pow((f - 700) / 250, 2)) +
            0.6 * math.exp(-math.pow((f - 1200) / 300, 2)) +
            0.3 * math.exp(-math.pow((f - 2600) / 400, 2));
        s += formants * math.sin(h * phase) / h;
      }
    } else {
      s = (random.nextDouble() * 2 - 1) * 0.15;
    }
    out[i] = (s * syllable * 9000).round().clamp(-32768, 32767);
  }
  return out;
}

List<Uint8List> _encode(
  Int16List pcm, {
  bool fec = false,
  int lossPercent = 0,
  int dredMs = 0,
}) {
  final encoder = OpusFrameEncoder(
    sampleRate: _rate,
    channels: 1,
    fec: fec,
    lossPercent: lossPercent,
    dredMs: dredMs,
  );
  final packets = [
    for (var i = 0; i < pcm.length ~/ _frame; i++)
      Uint8List.fromList(
        encoder.encode(
          Int16List.sublistView(pcm, i * _frame, (i + 1) * _frame),
        ),
      ),
  ];
  encoder.dispose();
  return packets;
}

({double snrDb, Map<OpusRecovery, int> methods}) _decodeWithLoss(
  List<Uint8List> packets,
  Set<int> lost, {
  bool useNext = true,
}) {
  final clean = OpusFrameDecoder(sampleRate: _rate, channels: 1)
    ..setQuality(complexity: 5);
  final lossy = OpusFrameDecoder(sampleRate: _rate, channels: 1)
    ..setQuality(complexity: 5);
  var signal = 0.0;
  var noise = 0.0;
  final methods = <OpusRecovery, int>{};
  for (var i = 0; i < packets.length; i++) {
    final reference = Int16List.fromList(clean.decode(packets[i]));
    if (!lost.contains(i)) {
      lossy.decode(packets[i]);
      continue;
    }
    var next = i + 1;
    while (lost.contains(next)) {
      next++;
    }
    final got = lossy.recover(
      useNext && next < packets.length ? packets[next] : null,
      offset: (next - i) * _frame,
      samplesPerChannel: _frame,
    );
    methods.update(lossy.lastRecovery, (n) => n + 1, ifAbsent: () => 1);
    for (var j = 0; j < reference.length; j++) {
      signal += reference[j] * reference[j];
      final d = reference[j] - (j < got.length ? got[j] : 0);
      noise += d * d;
    }
  }
  clean.dispose();
  lossy.dispose();
  return (snrDb: 10 * math.log(signal / noise) / math.ln10, methods: methods);
}

void main() {
  final pcm = _speechLike(300);
  final single = {for (var i = 7; i < 290; i += 11) i};
  final bursts = {
    for (var start = 20; start < 280; start += 40) ...[
      start,
      start + 1,
      start + 2,
    ],
  };

  group('recovering lost Opus packets (D190)', skip: _skip, () {
    test('FEC is only sent when the encoder expects loss', () {
      final r = _decodeWithLoss(_encode(pcm, fec: true), single);
      expect(r.methods.keys, [OpusRecovery.concealed]);
    });

    test('FEC in the next packet restores a lost one', () {
      final packets = _encode(pcm, fec: true, lossPercent: 10);
      final concealed = _decodeWithLoss(packets, single, useNext: false);
      final recovered = _decodeWithLoss(packets, single);
      expect(
        recovered.methods[OpusRecovery.fec],
        greaterThan(single.length ~/ 2),
      );
      expect(recovered.snrDb, greaterThan(concealed.snrDb + 4));
    });

    test('DRED fills a burst from a later packet', () {
      final packets = _encode(pcm, lossPercent: 10, dredMs: 100);
      final r = _decodeWithLoss(packets, bursts);
      expect(r.methods[OpusRecovery.dred], bursts.length);
    });

    for (final (protection, fec, dred) in [
      (LossProtection.channel, true, false),
      (LossProtection.channelAndDred, true, true),
      (LossProtection.none, false, false),
    ]) {
      test('${protection.name} on an FEC channel: FEC $fec, DRED $dred', () {
        final encoder = VoiceFrameEncoder.forConfig(
          const TxCodecConfig(
            sampleRate: _rate,
            channels: 1,
            bitrate: 32000,
            fec: true,
          ),
          1,
          protection: protection,
        );
        final packets = [
          for (var i = 0; i < pcm.length ~/ _frame; i++)
            Uint8List.fromList(
              encoder.encode(
                Int16List.sublistView(pcm, i * _frame, (i + 1) * _frame),
              ),
            ),
        ];
        encoder.dispose();
        final singles = _decodeWithLoss(packets, single).methods;
        final burst = _decodeWithLoss(packets, bursts).methods;
        expect(singles.containsKey(OpusRecovery.fec), fec);
        expect(burst.containsKey(OpusRecovery.dred), dred);
      });
    }

    test('without the next packet it conceals', () {
      final r = _decodeWithLoss(
        _encode(pcm, fec: true, lossPercent: 10, dredMs: 100),
        bursts,
        useNext: false,
      );
      expect(r.methods.keys, [OpusRecovery.concealed]);
    });

    test('every enhancement level decodes full frames', () {
      final packets = _encode(Int16List.sublistView(pcm, 0, 50 * _frame));
      for (final (complexity, extension) in [
        (0, false),
        (5, false),
        (6, false),
        (7, false),
        (7, true),
      ]) {
        final d = OpusFrameDecoder(sampleRate: _rate, channels: 2)
          ..setQuality(complexity: complexity, bandwidthExtension: extension);
        for (final p in packets) {
          expect(d.decode(p), hasLength(_frame * 2));
        }
        expect(
          d.recover(packets.first, offset: _frame, samplesPerChannel: _frame),
          hasLength(_frame * 2),
        );
        d.dispose();
      }
    });
  });
}
