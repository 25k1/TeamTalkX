import 'dart:async';

import 'native_channel.dart';

enum ForegroundAction { toggleTransmission, stopRecording }

class NotificationText {
  const NotificationText({
    required this.title,
    required this.channel,
    required this.transmitting,
    required this.recording,
    required this.transmit,
    required this.stopTransmitting,
    required this.stopRecording,
  });

  final String title;
  final String channel;
  final String transmitting;
  final String recording;
  final String transmit;
  final String stopTransmitting;
  final String stopRecording;

  Map<String, String> toMap() => {
    'title': title,
    'channel': channel,
    'transmitting': transmitting,
    'recording': recording,
    'transmit': transmit,
    'stopTransmitting': stopTransmitting,
    'stopRecording': stopRecording,
  };
}

abstract interface class ForegroundService {
  Stream<ForegroundAction> get actions;

  Future<void> start({
    required String serverName,
    required String channelName,
    required NotificationText text,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  });

  Future<void> update({
    required String serverName,
    required String channelName,
    required NotificationText text,
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
    required NotificationText text,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  }) => _send(
    'start',
    serverName,
    channelName,
    text,
    transmitting,
    recording,
    keepAwake,
  );

  @override
  Future<void> update({
    required String serverName,
    required String channelName,
    required NotificationText text,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  }) => _send(
    'update',
    serverName,
    channelName,
    text,
    transmitting,
    recording,
    keepAwake,
  );

  Future<void> _send(
    String method,
    String serverName,
    String channelName,
    NotificationText text,
    bool transmitting,
    bool recording,
    bool keepAwake,
  ) => _channel.invoke<void>(method, <String, Object>{
    'serverName': serverName,
    'channelName': channelName,
    'text': text.toMap(),
    'transmitting': transmitting,
    'recording': recording,
    'keepAwake': keepAwake,
  });

  @override
  Future<void> stop() => _channel.invoke<void>('stop');
}
