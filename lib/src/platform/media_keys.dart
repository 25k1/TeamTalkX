import 'dart:async';

import '../domain/media_keys.dart';
import 'native_channel.dart';

export '../domain/media_keys.dart';

abstract interface class MediaKeys {
  Stream<({MediaKey key, bool down})> get events;

  Future<void> configure({
    required bool session,
    required Set<MediaKey> mapped,
  });
}

class AndroidMediaKeys implements MediaKeys {
  AndroidMediaKeys() {
    _channel.setHandler((call) async {
      if (call.method != 'key') return;
      final args = call.arguments as Map;
      final key = MediaKey.fromName(args['key'] as String?);
      if (key == null) return;
      _events.add((key: key, down: args['down'] == true));
    });
  }

  final _channel = NativeChannel('media_keys');
  final _events = StreamController<({MediaKey key, bool down})>.broadcast();

  @override
  Stream<({MediaKey key, bool down})> get events => _events.stream;

  @override
  Future<void> configure({
    required bool session,
    required Set<MediaKey> mapped,
  }) => _channel.invokeQuiet('configure', {
    'session': session,
    'keys': [for (final k in mapped) k.name],
  });
}
