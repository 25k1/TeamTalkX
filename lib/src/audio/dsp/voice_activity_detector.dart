import 'dart:math' as math;
import 'dart:typed_data';

import 'voice_detector.dart';

class VoiceActivityDetector implements VoiceDetector {
  @override
  bool get needsSuppressorProbability => true;

  @override
  Duration get releaseHold => const Duration(seconds: 1);

  @override
  bool accept(
    Uint8List pcm, {
    required double? probability,
    required int sampleRate,
    required int channels,
    required int level,
    required bool currentlyActive,
  }) => probability == null
      ? acceptPcm(pcm, level: level, currentlyActive: currentlyActive)
      : acceptProbability(
          probability,
          level: level,
          currentlyActive: currentlyActive,
        );

  @override
  Future<void> dispose() async {}

  static const emaAlpha = 0.5;

  static const hysteresis = 0.15;

  static const maxLevel = 20;

  double _smoothedProbability = 0;
  double _smoothedRms = 0;

  double get smoothedProbability => _smoothedProbability;
  double get smoothedRms => _smoothedRms;

  @override
  void reset() {
    _smoothedProbability = 0;
    _smoothedRms = 0;
  }

  static double probabilityThreshold(int level) =>
      level.clamp(0, maxLevel) * 0.0475;

  static double rmsThreshold(int level) =>
      (level.clamp(0, maxLevel) / maxLevel) * 0.15;

  bool acceptProbability(
    double probability, {
    required int level,
    required bool currentlyActive,
  }) {
    _smoothedProbability =
        emaAlpha * probability + (1 - emaAlpha) * _smoothedProbability;
    final upper = probabilityThreshold(level);
    final lower = (upper - hysteresis).clamp(0.0, 1.0);
    return _smoothedProbability >= (currentlyActive ? lower : upper);
  }

  bool acceptPcm(
    Uint8List pcm, {
    required int level,
    required bool currentlyActive,
  }) {
    _smoothedRms = emaAlpha * rms(pcm) + (1 - emaAlpha) * _smoothedRms;
    final upper = rmsThreshold(level);
    final lower = (upper - hysteresis * upper).clamp(0.0, 1.0);
    return _smoothedRms >= (currentlyActive ? lower : upper);
  }

  static double rms(Uint8List pcm) {
    final samples = pcm.lengthInBytes ~/ 2;
    if (samples == 0) return 0;
    final bytes = ByteData.sublistView(pcm);
    var sumSquares = 0.0;
    for (var i = 0; i < samples; i++) {
      final sample = bytes.getInt16(i * 2, Endian.little).toDouble();
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / samples) / 32768.0;
  }
}
