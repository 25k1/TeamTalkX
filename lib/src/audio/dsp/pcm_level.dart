import 'dart:math' as math;
import 'dart:typed_data';

double pcmRms(Uint8List pcm) {
  final samples = int16View(pcm);
  final n = samples.length;
  if (n == 0) return 0;
  var sumSq = 0.0;
  for (var i = 0; i < n; i++) {
    final s = samples[i].toDouble();
    sumSq += s * s;
  }
  return math.sqrt(sumSq / n) / 32768.0;
}

Int16List int16View(Uint8List pcm) {
  final aligned = pcm.offsetInBytes.isEven ? pcm : Uint8List.fromList(pcm);
  return aligned.buffer.asInt16List(
    aligned.offsetInBytes,
    aligned.lengthInBytes ~/ 2,
  );
}
