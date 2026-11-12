import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../l10n/l10n.dart';
import 'failure_report.dart';

typedef L10nText = String Function(AppLocalizations l10n);

extension CommandRunner on WidgetRef {
  Future<bool> runCommand(
    ScaffoldMessengerState messenger,
    Future<void> Function() command, {
    L10nText? announce,
    required L10nText errorLabel,
  }) async {
    try {
      await command();
      if (announce != null) {
        read(
          announcerProvider,
        ).announce(announce(read(appLocalizationsProvider)));
      }
      return true;
    } on Object catch (e, st) {
      appLog.w(
        'command',
        errorLabel(lookupAppLocalizations(const Locale('en'))),
        e,
        st,
      );
      reportFailure(this, messenger, action: errorLabel, error: e);
      return false;
    }
  }
}
