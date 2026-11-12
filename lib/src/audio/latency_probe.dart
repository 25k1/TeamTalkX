import 'dart:math' as math;
import 'dart:typed_data';

class LatencyProbe {
  LatencyProbe({this.sampleRate = 48000, this.threshold = 0.3});

  final int sampleRate;

  final double threshold;

  final _captured = <int>[];

  int get capturedSamples => _captured.length;

  Int16List burst() {
    final samples = sampleRate ~/ 100;
    return Int16List.fromList([
      for (var i = 0; i < samples; i++)
        (math.sin(2 * math.pi * 1000 * i / sampleRate) *
                16384 *
                math.sin(math.pi * i / samples))
            .round(),
    ]);
  }

  void addCapture(Int16List samples) => _captured.addAll(samples);

  int? onsetAfter(int from) {
    const window = 48;
    if (from < 0 || _captured.length - from < window * 4) return null;
    final energies = <double>[];
    for (
      var start = from;
      start + window <= _captured.length;
      start += window
    ) {
      var sum = 0.0;
      for (var i = start; i < start + window; i++) {
        sum += _captured[i] * _captured[i];
      }
      energies.add(sum / window);
    }
    final peak = energies.reduce(math.max);
    final sorted = [...energies]..sort();
    final background = sorted[sorted.length ~/ 10];
    if (peak < background * 30 || peak < 1000) return null;
    final level = background + (peak - background) * threshold;
    final index = energies.indexWhere((e) => e >= level);
    return from + index * window;
  }

  double millis(int played, int onset) => (onset - played) * 1000 / sampleRate;
}
