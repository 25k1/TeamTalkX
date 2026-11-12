import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm_level.dart';

class AutoGainControl {
  AutoGainControl({
    this.targetRms = defaultTargetRms,
    this.minGain = 0.1,
    this.maxGain = 8.0,
    this.gateThreshold = 0.005,
    this.rmsAlpha = 0.4,
    this.attackAlpha = 0.5,
    this.releaseAlpha = 0.05,
  });

  static const defaultTargetRms = 0.17783;

  double targetRms;

  final double minGain;

  final double maxGain;

  final double gateThreshold;

  final double rmsAlpha;

  final double attackAlpha;

  final double releaseAlpha;

  double _gain = 1.0;
  double _smoothedRms = 0;
  bool _seeded = false;

  double get gain => _gain;

  static double targetForGainPercent(int percent) =>
      defaultTargetRms * percent / 50.0;

  void reset() {
    _gain = 1.0;
    _smoothedRms = 0;
    _seeded = false;
  }

  double gainFor(Uint8List pcm) {
    if (targetRms <= 0) return 0;

    final rms = pcmRms(pcm);
    if (rms < gateThreshold) return _gain;

    _smoothedRms = _seeded
        ? rmsAlpha * rms + (1 - rmsAlpha) * _smoothedRms
        : rms;
    _seeded = true;

    final desired = (targetRms / math.max(_smoothedRms, 1e-4))
        .clamp(minGain, maxGain)
        .toDouble();
    final alpha = desired < _gain ? attackAlpha : releaseAlpha;
    _gain += (desired - _gain) * alpha;
    return _gain;
  }
}
