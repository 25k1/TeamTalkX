import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/failures.dart';
import '../../app/settings/locale_providers.dart';
import '../../l10n/failure_messages.dart';
import '../../l10n/l10n.dart';
import 'ui.dart';

void reportFailure(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  required String Function(AppLocalizations l10n) action,
  required Object error,
}) {
  final l10n = ref.read(appLocalizationsProvider);
  final text = l10n.failureReport(
    action(l10n),
    l10n.failureMessage(failureFrom(error)),
  );
  messenger.showMessage(text);
  ref.read(announcerProvider).announceShown(text);
}
