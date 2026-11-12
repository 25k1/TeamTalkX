library;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

Locale resolveAppLocale(String? languageCode, Iterable<Locale> preferred) {
  final supported = AppLocalizations.supportedLocales;
  bool isSupported(String code) => supported.any((l) => l.languageCode == code);
  if (languageCode != null && isSupported(languageCode)) {
    return Locale(languageCode);
  }
  for (final locale in preferred) {
    if (isSupported(locale.languageCode)) return Locale(locale.languageCode);
  }
  return const Locale('en');
}

String localizedFileSize(AppLocalizations l10n, int bytes) {
  const kb = 1024;
  if (bytes >= kb * kb * kb) {
    return l10n.fileSizeGb((bytes / (kb * kb * kb)).toStringAsFixed(1));
  }
  if (bytes >= kb * kb) {
    return l10n.fileSizeMb((bytes / (kb * kb)).toStringAsFixed(1));
  }
  if (bytes >= kb) return l10n.fileSizeKb((bytes / kb).toStringAsFixed(0));
  return l10n.fileSizeBytes(bytes);
}
