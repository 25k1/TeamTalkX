import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/latency_probe.dart';

Int16List _recording(LatencyProbe probe, int length, int at, double level) {
  final random = math.Random(4);
  final out = Int16List.fromList([
    for (var i = 0; i < length; i++) random.nextInt(200) - 100,
  ]);
  final burst = probe.burst();
  for (var i = 0; i < burst.length && at + i < length; i++) {
    out[at + i] += (burst[i] * level).round();
  }
  return out;
}

void main() {
  test('the burst is 10 ms and fades in and out', () {
    final burst = LatencyProbe().burst();
    expect(burst, hasLength(480));
    expect(burst.first.abs(), lessThan(100));
    expect(burst.last.abs(), lessThan(1000));
    expect(burst.reduce(math.max), greaterThan(10000));
  });

  test('finds the onset of a faint burst to within a millisecond', () {
    final probe = LatencyProbe()
      ..addCapture(_recording(LatencyProbe(), 48000, 9600, 0.05));

    final onset = probe.onsetAfter(0)!;

    expect(onset, inInclusiveRange(9600 - 48, 9600 + 96));
    expect(probe.millis(4800, onset), closeTo(100, 2));
  });

  test('reports nothing when the burst never arrives', () {
    final probe = LatencyProbe()
      ..addCapture(_recording(LatencyProbe(), 48000, 0, 0));
    expect(probe.onsetAfter(0), isNull);
  });

  test('searches only after the given position', () {
    final probe = LatencyProbe()
      ..addCapture(_recording(LatencyProbe(), 48000, 4800, 0.5))
      ..addCapture(_recording(LatencyProbe(), 48000, 9600, 0.5));

    expect(probe.onsetAfter(24000)! - 48000, closeTo(9600, 96));
  });
}
