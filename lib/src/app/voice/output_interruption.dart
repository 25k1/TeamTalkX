import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OutputEffect { duck, mute }

enum InterruptionSource { call, otherApp, focus }

const duckGain = 0.25;

final outputInterruptionProvider =
    NotifierProvider<OutputInterruptionNotifier, OutputEffect?>(
      OutputInterruptionNotifier.new,
    );

class OutputInterruptionNotifier extends Notifier<OutputEffect?> {
  final _effects = <InterruptionSource, OutputEffect>{};

  @override
  OutputEffect? build() => null;

  void set(InterruptionSource source, OutputEffect? effect) {
    if (effect == null) {
      _effects.remove(source);
    } else {
      _effects[source] = effect;
    }
    state = _effects.containsValue(OutputEffect.mute)
        ? OutputEffect.mute
        : _effects.isEmpty
        ? null
        : OutputEffect.duck;
  }
}
