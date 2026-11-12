import 'dart:async';

import 'native_channel.dart';

abstract interface class Hotkeys {
  Stream<void> get pttDown;

  Stream<void> get pttUp;

  Stream<(int, String)> get captured;

  Future<void> setPttKey(int keyCode);

  Future<void> startCapture();

  Future<void> stopCapture();
}

class AndroidHotkeys implements Hotkeys {
  AndroidHotkeys() {
    _channel.setHandler((call) async {
      switch (call.method) {
        case 'pttDown':
          _pttDown.add(null);
        case 'pttUp':
          _pttUp.add(null);
        case 'captured':
          final args = call.arguments as Map;
          _captured.add((args['keyCode'] as int, args['label'] as String));
      }
    });
  }

  final _channel = NativeChannel('hotkey');
  final _pttDown = StreamController<void>.broadcast();
  final _pttUp = StreamController<void>.broadcast();
  final _captured = StreamController<(int, String)>.broadcast();

  @override
  Stream<void> get pttDown => _pttDown.stream;

  @override
  Stream<void> get pttUp => _pttUp.stream;

  @override
  Stream<(int, String)> get captured => _captured.stream;

  @override
  Future<void> setPttKey(int keyCode) =>
      _channel.invoke('setPttKey', {'keyCode': keyCode});

  @override
  Future<void> startCapture() => _channel.invoke('startCapture');

  @override
  Future<void> stopCapture() => _channel.invoke('stopCapture');
}
