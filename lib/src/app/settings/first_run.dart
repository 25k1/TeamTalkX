import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_providers.dart';

final firstRunProvider = NotifierProvider<FirstRunNotifier, bool>(
  FirstRunNotifier.new,
);

class FirstRunNotifier extends Notifier<bool> {
  static const _key = 'first_run_done';

  static const _usedBefore = [
    'nickname',
    'server_list',
    'speech_output',
    'app_language',
    'user_configs',
  ];

  @override
  bool build() {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_key) ?? false) return false;
    if (_usedBefore.any(prefs.containsKey)) {
      unawaited(prefs.setBool(_key, true));
      return false;
    }
    return true;
  }

  void complete() {
    unawaited(ref.read(sharedPreferencesProvider).setBool(_key, true));
    state = false;
  }
}
