import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

abstract class PrefsNotifier<T> extends Notifier<T> {
  SharedPreferences get prefs => ref.read(sharedPreferencesProvider);

  void saveBool(String key, bool value, T Function(T) update) {
    unawaited(prefs.setBool(key, value));
    state = update(state);
  }

  void saveInt(String key, int value, T Function(T) update) {
    unawaited(prefs.setInt(key, value));
    state = update(state);
  }

  void saveString(String key, String value, T Function(T) update) {
    unawaited(prefs.setString(key, value));
    state = update(state);
  }
}
