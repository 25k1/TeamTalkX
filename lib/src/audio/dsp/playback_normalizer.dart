import 'dart:math' as math;
import 'dart:typed_data';

class PlaybackNormalizer {
  PlaybackNormalizer({
    this.sampleRate = 48000,
    this.channels = 2,
    this.targetDb = -20,
    this.minDb = -10,
    this.maxDb = 15,
    this.gateDb = -50,
    this.dbPerSecond = 3,
  });

  final int sampleRate;
  final int channels;
  final double targetDb;
  final double minDb;
  final double maxDb;

  final double gateDb;

  final double dbPerSecond;

  double _gainDb = 0;

  double get gainDb => _gainDb;
  double get gain => math.pow(10, _gainDb / 20).toDouble();

  double update(Int16List pcm) {
    if (pcm.isEmpty) return gain;
    var sum = 0.0;
    for (final s in pcm) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / pcm.length) / 32768;
    final levelDb = rms <= 0 ? -120.0 : 20 * math.log(rms) / math.ln10;
    if (levelDb >= gateDb) {
      final wanted = (targetDb - levelDb).clamp(minDb, maxDb);
      final seconds = pcm.length / channels / sampleRate;
      final step = dbPerSecond * seconds;
      _gainDb += (wanted - _gainDb).clamp(-step, step);
    }
    return gain;
  }

  void reset() => _gainDb = 0;
}
