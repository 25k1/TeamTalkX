import 'dart:async';

import 'native_channel.dart';

abstract interface class PmNotifications {
  Stream<int> get openRequests;

  Stream<(int, String)> get replies;

  Future<void> show({
    required int userId,
    required String title,
    required String message,
  });

  Future<void> cancel(int userId);

  Future<int> initialPm();
}

class AndroidPmNotifications implements PmNotifications {
  AndroidPmNotifications() {
    _channel.setHandler((call) async {
      switch (call.method) {
        case 'openPm':
          _open.add(call.arguments as int);
        case 'reply':
          final args = call.arguments as Map;
          _replies.add((args['userId'] as int, args['text'] as String));
      }
    });
  }

  final _channel = NativeChannel('pmnotify');
  final _open = StreamController<int>.broadcast();
  final _replies = StreamController<(int, String)>.broadcast();

  @override
  Stream<int> get openRequests => _open.stream;

  @override
  Stream<(int, String)> get replies => _replies.stream;

  @override
  Future<void> show({
    required int userId,
    required String title,
    required String message,
  }) => _channel.invoke('show', {
    'userId': userId,
    'title': title,
    'message': message,
  });

  @override
  Future<void> cancel(int userId) =>
      _channel.invoke('cancel', {'userId': userId});

  @override
  Future<int> initialPm() async =>
      await _channel.invoke<int>('getInitialPm') ?? 0;
}
