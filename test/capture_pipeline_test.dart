import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/capture_pipeline.dart';
import 'package:teamtalkx/src/audio/dsp/noise_suppression.dart';
import 'package:teamtalkx/src/audio/dsp/voice_detector.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';

class _FakeSuppressor implements NoiseSuppressor {
  final configured = <(int, int, double)>[];
  int resets = 0;

  @override
  void configure({
    required int sampleRate,
    required int channels,
    required double wet,
  }) => configured.add((sampleRate, channels, wet));

  @override
  NoiseSuppressionResult process(Uint8List pcm) {
    final count = pcm.lengthInBytes ~/ 2;
    final samples = Int16List(count)..fillRange(0, count, 7);
    return NoiseSuppressionResult(
      pcm: samples.buffer.asUint8List(),
      voiceProbability: 0.9,
    );
  }

  @override
  void reset() => resets++;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDetector implements VoiceDetector {
  bool hears = false;
  final probabilities = <double?>[];
  final firstSamples = <int>[];
  int resets = 0;
  bool disposed = false;

  @override
  bool accept(
    Uint8List pcm, {
    required double? probability,
    required int sampleRate,
    required int channels,
    required int level,
    required bool currentlyActive,
  }) {
    probabilities.add(probability);
    firstSamples.add(Int16List.view(pcm.buffer, pcm.offsetInBytes)[0]);
    return hears;
  }

  @override
  bool get needsSuppressorProbability => false;
  @override
  Duration get releaseHold => Duration.zero;
  @override
  void reset() => resets++;
  @override
  Future<void> dispose() async => disposed = true;
}

Uint8List _frame(int value) =>
    (Int16List(960)..fillRange(0, 960, value)).buffer.asUint8List();

int _first(CaptureFrame frame) =>
    Int16List.view(frame.pcm.buffer, frame.pcm.offsetInBytes)[0];

void main() {
  late _FakeSuppressor suppressor;
  late List<(VoiceDetectorKind, Uint8List?)> created;
  late _FakeDetector detector;
  late CapturePipeline pipeline;

  setUp(() {
    suppressor = _FakeSuppressor();
    created = [];
    detector = _FakeDetector();
    pipeline = CapturePipeline(
      createSuppressor: () => suppressor,
      createDetector: (kind, model) {
        created.add((kind, model));
        return detector;
      },
    );
  });

  const plain = CaptureSettings(sampleRate: 48000, channels: 1, gain: 1.5);
  const vox = CaptureSettings(
    sampleRate: 48000,
    channels: 1,
    voiceDetection: true,
  );

  test('nothing is processed before it is configured', () {
    final out = pipeline.process(_frame(1), transmit: true);
    expect(out.frames, isEmpty);
    expect(out.voice, isNull);
  });

  test('transmitted frames are encoded with the fixed gain', () {
    pipeline.configure(plain);

    final out = pipeline.process(_frame(1), transmit: true);

    expect(out.frames.single.gain, 1.5);
    expect(_first(out.frames.single), 1);
    expect(out.voice, isNull);
    expect(pipeline.process(_frame(1), transmit: false).frames, isEmpty);
  });

  test('noise suppression replaces the audio when it is on', () {
    pipeline.configure(
      const CaptureSettings(
        sampleRate: 48000,
        channels: 1,
        noiseSuppression: true,
        noiseSuppressionLevel: 0.4,
      ),
    );

    final out = pipeline.process(_frame(1), transmit: true);

    expect(suppressor.configured.single, (48000, 1, 0.4));
    expect(_first(out.frames.single), 7);
  });

  test('voice detection sees the raw audio and its RNNoise probability', () {
    pipeline.configure(
      const CaptureSettings(
        sampleRate: 48000,
        channels: 1,
        voiceDetection: true,
        detector: VoiceDetectorKind.rnnoise,
      ),
    );
    detector.hears = true;

    final out = pipeline.process(_frame(3), transmit: false);

    expect(out.voice, isTrue);
    expect(detector.firstSamples.single, 3, reason: 'not the denoised audio');
    expect(detector.probabilities.single, 0.9);
    expect(created.single.$1, VoiceDetectorKind.rnnoise);
  });

  test('VOX keeps 200 ms of pre-roll and sends it when told to', () {
    pipeline.configure(vox);
    for (var i = 1; i <= 15; i++) {
      pipeline.process(_frame(i), transmit: false);
    }

    final out = pipeline.process(
      _frame(99),
      transmit: true,
      flushPreRoll: true,
    );

    expect(out.frames.map(_first), [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 99]);
    expect(pipeline.process(_frame(100), transmit: true).frames.map(_first), [
      100,
    ]);
  });

  test('push-to-talk drops the pre-roll instead of sending it', () {
    pipeline.configure(vox);
    pipeline.process(_frame(1), transmit: false);

    final out = pipeline.process(_frame(2), transmit: true);

    expect(out.frames.map(_first), [2]);
  });

  test('automatic gain control replaces the fixed gain and adapts', () {
    List<double> gains(int level) {
      final agc = CapturePipeline(createSuppressor: () => suppressor)
        ..configure(
          const CaptureSettings(
            sampleRate: 48000,
            channels: 1,
            agc: true,
            gain: 1.5,
          ),
        );
      return [
        for (var i = 0; i < 25; i++)
          agc.process(_frame(level), transmit: true).frames.single.gain,
      ];
    }

    final quiet = gains(300);
    final loud = gains(20000);

    expect(quiet.last, greaterThan(quiet.first), reason: 'it ramps up');
    expect(quiet.last, greaterThan(loud.last * 4));
  });

  test('a new detector kind replaces the detector; Silero gets the model', () {
    final model = Uint8List.fromList([1, 2, 3]);
    pipeline
      ..sileroModel = model
      ..configure(vox)
      ..process(_frame(1), transmit: false)
      ..configure(
        const CaptureSettings(
          sampleRate: 48000,
          channels: 1,
          voiceDetection: true,
          detector: VoiceDetectorKind.rnnoise,
        ),
      )
      ..process(_frame(1), transmit: false);

    expect(created.map((c) => c.$1), [
      VoiceDetectorKind.silero,
      VoiceDetectorKind.rnnoise,
    ]);
    expect(created.first.$2, same(model));
  });

  test('reset clears the pre-roll and the detector', () {
    pipeline.configure(vox);
    pipeline.process(_frame(1), transmit: false);

    pipeline.reset();
    final out = pipeline.process(_frame(2), transmit: true, flushPreRoll: true);

    expect(out.frames.map(_first), [2]);
    expect(detector.resets, 1);
  });
}
