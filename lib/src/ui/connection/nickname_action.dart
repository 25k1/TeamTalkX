import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../app/settings/settings_providers.dart';
import '../../diagnostics/log.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../a11y/dialogs.dart';

Future<void> editNickname(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final client = ref.read(teamTalkClientProvider);
  final settings = ref.read(settingsProvider.notifier);
  final loggedIn = ref.read(connectionProvider) is LoggedIn;
  final live = client.state.users[client.state.myUserId]?.nickname ?? '';
  final initial = live.isNotEmpty ? live : ref.read(settingsProvider).nickname;

  final l10n = context.l10n;
  final nickname = await promptText(
    context,
    title: l10n.commonNickname,
    label: l10n.commonNickname,
    initialValue: initial,
    submitLabel: l10n.commonSave,
    barrierDismissible: false,
  );
  if (nickname == null) return;
  final trimmed = nickname.trim();
  try {
    settings.setNickname(trimmed);
    if (loggedIn) await client.changeNickname(trimmed);
  } on Object catch (e, st) {
    appLog.w('status', 'Nickname change failed', e, st);
    reportFailure(
      ref,
      messenger,
      action: (l) => l.actionChangeNickname,
      error: e,
    );
  }
}
