import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/settings/settings_file.dart';
import '../../diagnostics/log.dart';
import '../../l10n/l10n.dart';
import '../a11y/dialogs.dart';
import '../common/export.dart';
import '../common/failure_report.dart';
import '../common/ui.dart';

Future<void> exportSettingsFile(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final withPasswords = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.settingsFileExport),
      content: Text(l10n.settingsFileExportPasswords),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.settingsFileWithoutPasswords),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.settingsFileWithPasswords),
        ),
      ],
    ),
  );
  if (withPasswords == null || !context.mounted) return;
  String? passphrase;
  if (withPasswords) {
    passphrase = await showDialog<String>(
      context: context,
      builder: (_) => const _NewPassphraseDialog(),
    );
    if (passphrase == null) return;
  }
  messenger.showMessage(l10n.settingsFileWorking);
  final String content;
  try {
    content = await ref
        .read(settingsFileProvider)
        .export(
          appVersion: ref.read(appVersionProvider),
          passphrase: passphrase,
        );
  } on Object catch (e, st) {
    appLog.w('settings', 'Exporting settings failed', e, st);
    reportFailure(ref, messenger, action: (l) => l.actionExport, error: e);
    return;
  }
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  await exportToDownloads(
    ref,
    messenger,
    fileName:
        'teamtalkx-settings-${now.year}${two(now.month)}${two(now.day)}.json',
    content: content,
  );
}

Future<void> importSettingsFile(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final picked = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(label: l10n.settingsFileType, extensions: const ['json']),
    ],
  );
  if (picked == null || !context.mounted) return;
  final service = ref.read(settingsFileProvider);
  final SettingsFile file;
  try {
    file = SettingsFile.parse(
      utf8.decode(await picked.readAsBytes(), allowMalformed: true),
    );
  } on FormatException catch (e) {
    appLog.w('settings', 'Not a settings file', e);
    messenger.showMessage(l10n.settingsFileNotOne);
    return;
  }
  if (!context.mounted) return;

  var passwords = const <String, Object?>{};
  if (file.passwords != null) {
    while (true) {
      final passphrase = await promptText(
        context,
        title: l10n.settingsFilePassphraseTitle,
        label: l10n.settingsFilePassphrase,
        obscureText: true,
        submitLabel: l10n.settingsFileOpenPasswords,
        cancelLabel: l10n.settingsFileSkipPasswords,
      );
      if (passphrase == null || !context.mounted) break;
      messenger.showMessage(l10n.settingsFileWorking);
      try {
        passwords = await service.openPasswords(file, passphrase);
        break;
      } on SettingsPassphraseWrong {
        messenger.showMessage(l10n.settingsFileWrongPassphrase);
      } on FormatException catch (e) {
        appLog.w('settings', 'Damaged passwords in a settings file', e);
        messenger.showMessage(l10n.settingsFileNotOne);
        break;
      }
      if (!context.mounted) return;
    }
  }
  if (!context.mounted) return;

  final preview = await service.preview(file);
  if (!context.mounted) return;
  final confirmed = await confirm(
    context,
    title: l10n.settingsFileImportTitle,
    message: [
      l10n.settingsFileImportSettings(preview.settings),
      l10n.settingsFileImportServers(preview.newServers, preview.knownServers),
      if (file.passwords != null)
        passwords.isEmpty
            ? l10n.settingsFileImportNoPasswords
            : l10n.settingsFileImportPasswords,
    ].join('\n\n'),
    confirmLabel: l10n.commonImport,
  );
  if (!confirmed) return;
  try {
    await service.apply(file, passwords: passwords);
    messenger.showMessage(l10n.settingsFileImported);
  } on Object catch (e, st) {
    appLog.w('settings', 'Importing settings failed', e, st);
    reportFailure(ref, messenger, action: (l) => l.actionImport, error: e);
  }
}

class _NewPassphraseDialog extends StatefulWidget {
  const _NewPassphraseDialog();

  @override
  State<_NewPassphraseDialog> createState() => _NewPassphraseDialogState();
}

class _NewPassphraseDialogState extends State<_NewPassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    if (_first.text.isEmpty) {
      setState(() => _error = l10n.settingsFilePassphraseEmpty);
    } else if (_first.text != _second.text) {
      setState(() => _error = l10n.settingsFilePassphraseMismatch);
    } else {
      Navigator.of(context).pop(_first.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsFilePassphraseTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.settingsFilePassphraseNote),
            TextField(
              controller: _first,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.settingsFilePassphrase,
              ),
            ),
            TextField(
              controller: _second,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.settingsFilePassphraseRepeat,
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.commonOk)),
      ],
    );
  }
}
