import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/tts_info.dart';
import '../platform_services.dart';
import 'settings_providers.dart';

final ttsEnginesProvider = FutureProvider<List<TtsEngineInfo>>(
  (ref) => ref.read(ttsProvider).getEngines(),
);

final ttsLanguagesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(speechSettingsProvider.select((s) => s.ttsEngine));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return ref.read(ttsProvider).getLanguages();
});

final ttsVoicesProvider = FutureProvider<List<TtsVoiceInfo>>((ref) async {
  ref.watch(speechSettingsProvider.select((s) => s.ttsEngine));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return ref.read(ttsProvider).getVoices();
});
