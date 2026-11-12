import 'dart:async';

import '../domain/audio_output.dart';
import 'native_channel.dart';

export '../domain/audio_output.dart';

abstract interface class AudioRouting {
  Future<List<AudioOutputDevice>> outputs();

  Stream<void> get outputsChanged;

  Future<void> setCommunication({required bool on, int deviceId = 0});
}

class AndroidAudioRouting implements AudioRouting {
  AndroidAudioRouting() {
    _channel.setHandler((call) async {
      if (call.method == 'outputsChanged') _changed.add(null);
    });
  }

  final _channel = NativeChannel('audio_routing');
  final _changed = StreamController<void>.broadcast();

  @override
  Future<List<AudioOutputDevice>> outputs() async {
    final list =
        await _channel.invokeList<Map<Object?, Object?>>('outputs') ?? const [];
    return [
      for (final m in list)
        if (AudioOutputKind.fromName(m['kind'] as String?) case final kind?)
          AudioOutputDevice(
            id: m['id']! as int,
            kind: kind,
            name: (m['name'] as String?) ?? '',
          ),
    ];
  }

  @override
  Stream<void> get outputsChanged => _changed.stream;

  @override
  Future<void> setCommunication({required bool on, int deviceId = 0}) =>
      _channel.invokeQuiet('setCommunication', {
        'on': on,
        'deviceId': deviceId,
      });
}
