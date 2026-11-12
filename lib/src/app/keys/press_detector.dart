import 'dart:async';

import '../../domain/media_keys.dart';

class PressDetector {
  PressDetector({
    required this.hasLongPress,
    required this.onPress,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.longPress = const Duration(milliseconds: 500),
  });

  final bool Function(MediaKey key) hasLongPress;
  final void Function(MediaKey key) onPress;
  final void Function(MediaKey key) onHoldStart;
  final void Function(MediaKey key) onHoldEnd;
  final Duration longPress;

  final _timers = <MediaKey, Timer>{};
  final _held = <MediaKey>{};
  final _down = <MediaKey>{};

  void down(MediaKey key) {
    if (!_down.add(key)) return;
    if (!hasLongPress(key)) {
      onPress(key);
      return;
    }
    _timers[key] = Timer(longPress, () {
      _timers.remove(key);
      _held.add(key);
      onHoldStart(key);
    });
  }

  void up(MediaKey key) {
    if (!_down.remove(key)) return;
    final timer = _timers.remove(key);
    if (timer != null) {
      timer.cancel();
      onPress(key);
    } else if (_held.remove(key)) {
      onHoldEnd(key);
    }
  }

  void reset({bool endHolds = true}) {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _down.clear();
    final held = List.of(_held);
    _held.clear();
    if (endHolds) held.forEach(onHoldEnd);
  }
}
