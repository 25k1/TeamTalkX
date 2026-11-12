import 'dart:math' as math;

const soundVolumeMin = 0;
const soundVolumeMax = 32000;

int refVolume(double percent) {
  final p = percent.clamp(0, 100).toDouble();
  return (82.832 * math.exp(0.0508 * p) - 50).toInt();
}

int refVolumeToPercent(int volume, {int step = 5}) {
  final v = volume.clamp(soundVolumeMin, soundVolumeMax);
  if (v <= 0) return 0;
  final d = math.log((v + 50) / 82.832) / 0.0508;
  final raw = (d + 0.5).toInt().clamp(0, 100);
  if (step <= 1) return raw;
  return ((raw / step).round() * step).clamp(0, 100);
}

int refGain(double percent) => percent == 0 ? 0 : refVolume(percent);

const volumeNormal = 1000;
const volumePercentMax = 300;

int volumeFromPercent(int percent) =>
    percent.clamp(0, volumePercentMax) * volumeNormal ~/ 100;

int volumeToPercent(int volume) =>
    (volume * 100 / volumeNormal).round().clamp(0, volumePercentMax);

double gainFromVolume(int volume) =>
    (volume / volumeNormal).clamp(0.0, volumePercentMax / 100);
