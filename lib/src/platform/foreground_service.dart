import 'dart:async';

import 'native_channel.dart';

enum ForegroundAction { toggleTransmission, stopRecording }

abstract interface class ForegroundService {
  Stream<ForegroundAction> get actions;

  Future<void> start({
    required String serverName,
    required String channelName,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  });

  Future<void> update({
    required String serverName,
    required String channelName,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  });

  Future<void> stop();
}

class AndroidForegroundService implements ForegroundService {
  AndroidForegroundService() {
    _actionChannel.setHandler((call) async {
      switch (call.method) {
        case 'toggleTransmission':
          _actions.add(ForegroundAction.toggleTransmission);
        case 'stopRecording':
          _actions.add(ForegroundAction.stopRecording);
      }
    });
  }

  final _channel = NativeChannel('foreground');
  final _actionChannel = NativeChannel('foreground_action');
  final _actions = StreamController<ForegroundAction>.broadcast();

  @override
  Stream<ForegroundAction> get actions => _actions.stream;

  @override
  Future<void> start({
    required String serverName,
    required String channelName,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  }) => _send(
    'start',
    serverName,
    channelName,
    transmitting,
    recording,
    keepAwake,
  );

  @override
  Future<void> update({
    required String serverName,
    required String channelName,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  }) => _send(
    'update',
    serverName,
    channelName,
    transmitting,
    recording,
    keepAwake,
  );

  Future<void> _send(
    String method,
    String serverName,
    String channelName,
    bool transmitting,
    bool recording,
    bool keepAwake,
  ) => _channel.invoke<void>(method, <String, Object>{
    'serverName': serverName,
    'channelName': channelName,
    'transmitting': transmitting,
    'recording': recording,
    'keepAwake': keepAwake,
  });

  @override
  Future<void> stop() => _channel.invoke<void>('stop');
}
