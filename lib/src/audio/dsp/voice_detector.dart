import 'dart:typed_data';

abstract interface class VoiceDetector {
  bool accept(
    Uint8List pcm, {
    required double? probability,
    required int sampleRate,
    required int channels,
    required int level,
    required bool currentlyActive,
  });

  bool get needsSuppressorProbability;

  Duration get releaseHold;

  void reset();

  Future<void> dispose();
}
