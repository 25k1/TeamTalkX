import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/native_haptics.dart';
import '../platform_services.dart';
import 'event_config.dart';

final hapticPlayerProvider = Provider<HapticPlayer>((ref) {
  final player = HapticPlayer(ref.read(hapticsProvider));
  ref.onDispose(player.dispose);
  return player;
});

class HapticPlayer {
  HapticPlayer(this._haptics);

  final Haptics _haptics;
  Timer? _timer;

  static const _sliceMs = 12;
  static const _leadMs = 45;
  static const _tailMs = 70;

  int _amplitude(HapticStrength s) => switch (s) {
    HapticStrength.light => 120,
    HapticStrength.medium => 190,
    HapticStrength.heavy => 255,
  };

  void play(List<HapticStep> pattern) {
    _timer?.cancel();
    if (pattern.isEmpty) return;
    final (timings, amplitudes) = _buildWaveform(pattern);
    unawaited(
      _haptics.waveform(timings, amplitudes).then((played) {
        if (!played) _playImpacts(pattern, 0);
      }),
    );
  }

  (List<int>, List<int>) _buildWaveform(List<HapticStep> pattern) {
    final amps = [for (final s in pattern) _amplitude(s.strength)];
    final timings = <int>[];
    final values = <int>[];

    void segment(int from, int to, int durationMs) {
      final slices = (durationMs / _sliceMs).round().clamp(1, 1000);
      final sliceMs = (durationMs / slices).round().clamp(1, 1000);
      for (var j = 1; j <= slices; j++) {
        final t = j / slices;
        final eased = (1 - cos(pi * t)) / 2;
        timings.add(sliceMs);
        values.add((from + (to - from) * eased).round().clamp(0, 255));
      }
    }

    segment(0, amps.first, _leadMs);
    for (var i = 0; i < amps.length - 1; i++) {
      final gap = pattern[i].gapMs <= 0 ? 40 : pattern[i].gapMs;
      segment(amps[i], amps[i + 1], gap);
    }
    segment(amps.last, 0, _tailMs);
    return (timings, values);
  }

  Future<void> _impact(HapticStrength strength) => switch (strength) {
    HapticStrength.light => HapticFeedback.lightImpact(),
    HapticStrength.medium => HapticFeedback.mediumImpact(),
    HapticStrength.heavy => HapticFeedback.heavyImpact(),
  };

  void _playImpacts(List<HapticStep> pattern, int index) {
    if (index >= pattern.length) return;
    unawaited(_impact(pattern[index].strength));
    if (index + 1 >= pattern.length) return;
    _timer = Timer(
      Duration(milliseconds: pattern[index].gapMs),
      () => _playImpacts(pattern, index + 1),
    );
  }

  void dispose() {
    _timer?.cancel();
  }
}
