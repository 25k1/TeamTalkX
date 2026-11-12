import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import 'settings_providers.dart';

final deviceLocalesProvider = Provider<List<Locale>>(
  (ref) => PlatformDispatcher.instance.locales,
);

final appLocaleProvider = Provider<Locale>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return resolveAppLocale(language.code, ref.watch(deviceLocalesProvider));
});

final appLocalizationsProvider = Provider<AppLocalizations>(
  (ref) => lookupAppLocalizations(ref.watch(appLocaleProvider)),
);
