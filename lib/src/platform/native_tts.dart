import '../domain/tts_info.dart';
import 'native_channel.dart';

export '../domain/tts_info.dart';

abstract interface class Tts {
  Future<bool> init({String engine = ''});

  Future<List<TtsEngineInfo>> getEngines();

  Future<List<String>> getLanguages();

  Future<List<TtsVoiceInfo>> getVoices();

  Future<void> configure({
    required String language,
    required String voice,
    required double rate,
    required double pitch,
    required double volume,
    required bool accessibilityStream,
  });

  Future<void> speak(String text, {bool interrupt = false});

  Future<void> stop();
}

class AndroidTts implements Tts {
  final _channel = NativeChannel('tts');

  @override
  Future<bool> init({String engine = ''}) async =>
      await _channel.invoke<bool>('init', {'engine': engine}) ?? false;

  @override
  Future<List<TtsEngineInfo>> getEngines() async {
    final raw = await _channel.invokeList<Map<Object?, Object?>>('getEngines');
    return [
      for (final entry in raw ?? const <Map<Object?, Object?>>[])
        TtsEngineInfo(
          name: entry['name'] as String? ?? '',
          label: entry['label'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<List<String>> getLanguages() async =>
      await _channel.invokeList<String>('getLanguages') ?? const [];

  @override
  Future<List<TtsVoiceInfo>> getVoices() async {
    final raw = await _channel.invokeList<Map<Object?, Object?>>('getVoices');
    return [
      for (final entry in raw ?? const <Map<Object?, Object?>>[])
        TtsVoiceInfo(
          name: entry['name'] as String? ?? '',
          locale: entry['locale'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<void> configure({
    required String language,
    required String voice,
    required double rate,
    required double pitch,
    required double volume,
    required bool accessibilityStream,
  }) => _channel.invoke<void>('configure', {
    'language': language,
    'voice': voice,
    'rate': rate,
    'pitch': pitch,
    'volume': volume,
    'accessibilityStream': accessibilityStream,
  });

  @override
  Future<void> speak(String text, {bool interrupt = false}) =>
      _channel.invoke<void>('speak', {'text': text, 'interrupt': interrupt});

  @override
  Future<void> stop() => _channel.invoke<void>('stop');
}
