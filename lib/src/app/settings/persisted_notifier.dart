import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_providers.dart';

abstract class PersistedNotifier<T> extends Notifier<T> {
  String get prefsKey;
  T get defaultValue;
  T decode(String raw);
  String encode(T value);

  @override
  T build() {
    final raw = ref.read(sharedPreferencesProvider).getString(prefsKey);
    return raw == null ? defaultValue : decode(raw);
  }

  void set(T value) {
    unawaited(
      ref.read(sharedPreferencesProvider).setString(prefsKey, encode(value)),
    );
    state = value;
  }

  void reset() {
    unawaited(ref.read(sharedPreferencesProvider).remove(prefsKey));
    state = defaultValue;
  }
}

abstract class PersistedEnumNotifier<T extends Enum>
    extends PersistedNotifier<T> {
  List<T> get values;

  @override
  T decode(String raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => defaultValue);

  @override
  String encode(T value) => value.name;
}

abstract class PersistedStringNotifier extends PersistedNotifier<String> {
  @override
  String decode(String raw) => raw;

  @override
  String encode(String value) => value;
}
