import 'dart:async';

import '../domain/call_state.dart';
import 'native_channel.dart';

export '../domain/call_state.dart';

enum FocusChange {
  ducked,
  regained,

  lost;

  static FocusChange? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

abstract interface class Interruptions {
  Stream<CallState> get callState;

  Stream<bool> get otherAppPlaying;

  Future<void> start();
  Future<void> stop();

  Future<void> duckOthers({required bool voiceCall});
  Future<void> stopDuckingOthers();

  Stream<FocusChange> get focusChanges;
}

class AndroidInterruptions implements Interruptions {
  AndroidInterruptions() {
    _channel.setHandler((call) async {
      switch (call.method) {
        case 'callState':
          _callState.add(CallState.fromName(call.arguments as String?));
        case 'otherPlaying':
          _otherPlaying.add(call.arguments as bool);
        case 'focus':
          if (FocusChange.fromName(call.arguments as String?) case final c?) {
            _focus.add(c);
          }
      }
    });
  }

  final _channel = NativeChannel('interruptions');
  final _callState = StreamController<CallState>.broadcast();
  final _otherPlaying = StreamController<bool>.broadcast();
  final _focus = StreamController<FocusChange>.broadcast();

  @override
  Stream<CallState> get callState => _callState.stream;

  @override
  Stream<bool> get otherAppPlaying => _otherPlaying.stream;

  @override
  Future<void> start() => _channel.invokeQuiet('start');

  @override
  Future<void> stop() => _channel.invokeQuiet('stop');

  @override
  Future<void> duckOthers({required bool voiceCall}) =>
      _channel.invokeQuiet('duckOthers', {'voiceCall': voiceCall});

  @override
  Future<void> stopDuckingOthers() => _channel.invokeQuiet('stopDuckingOthers');

  @override
  Stream<FocusChange> get focusChanges => _focus.stream;
}
