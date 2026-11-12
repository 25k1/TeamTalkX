import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/users/user_config.dart';
import '../../diagnostics/log.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import '../common/export.dart';
import '../common/ui.dart';
import '../settings/settings_widgets.dart';

List<(int, String)> _subLabels(AppLocalizations l10n) => [
  (Subscriptions.voice, l10n.rememberedSubVoice),
  (Subscriptions.channelMsg, l10n.rememberedSubChannel),
  (Subscriptions.userMsg, l10n.rememberedSubPrivate),
  (Subscriptions.broadcastMsg, l10n.rememberedSubBroadcast),
  (Subscriptions.customMsg, l10n.rememberedSubCustom),
  (Subscriptions.mediaFile, l10n.rememberedSubMedia),
  (Subscriptions.interceptVoice, l10n.rememberedInterceptVoice),
  (Subscriptions.interceptUserMsg, l10n.rememberedInterceptPrivate),
  (Subscriptions.interceptChannelMsg, l10n.rememberedInterceptChannel),
  (Subscriptions.interceptCustomMsg, l10n.rememberedInterceptCustom),
  (Subscriptions.interceptMediaFile, l10n.rememberedInterceptMedia),
];

String _displayName(AppLocalizations l10n, StoredUserConfig config) {
  final name = config.username.isEmpty
      ? l10n.rememberedNoUsername
      : config.username;
  return config.clientName.isEmpty ? name : '$name ${config.clientName}';
}

String _summary(AppLocalizations l10n, StoredUserConfig config) {
  final parts = <String>[
    if (config.muted) l10n.commonMuted,
    if (config.volumePercent case final percent?)
      l10n.rememberedVolume(percent),
    if (config.mediaMuted) l10n.userMediaMuted,
    if (config.mediaVolumePercent case final percent?)
      l10n.rememberedMediaVolume(percent),
    for (final (mask, label) in _subLabels(l10n))
      if ((config.subscriptions ?? 0) & mask != 0) label,
  ];
  return parts.isEmpty ? l10n.rememberedNoOverrides : parts.join(', ');
}

class RememberedUsersScreen extends ConsumerWidget {
  const RememberedUsersScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    await exportToDownloads(
      ref,
      ScaffoldMessenger.of(context),
      fileName: 'teamtalk_user_settings.json',
      content: ref.read(userConfigsProvider.notifier).exportJson(),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final typeGroup = XTypeGroup(
        label: l10n.rememberedJson,
        extensions: const ['json'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final count = ref
          .read(userConfigsProvider.notifier)
          .importJson(await file.readAsString());
      messenger.showMessage(
        count < 0 ? l10n.rememberedReadFailed : l10n.rememberedImported(count),
      );
    } on Object catch (e, st) {
      appLog.w('users', 'Importing user settings failed', e, st);
      reportFailure(ref, messenger, action: (l) => l.actionImport, error: e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(userConfigsProvider);
    final notifier = ref.read(userConfigsProvider.notifier);
    final servers = configs.entries.toList();
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsRememberedUsers),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: l10n.commonImport,
            onPressed: () => _import(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: l10n.commonExport,
            onPressed: servers.isEmpty ? null : () => _export(context, ref),
          ),
          if (servers.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.rememberedForgetAll,
              onPressed: () async {
                if (await confirm(
                  context,
                  title: l10n.rememberedForgetAllConfirm,
                  confirmLabel: l10n.rememberedForgetAll,
                )) {
                  notifier.clearAll();
                }
              },
            ),
        ],
      ),
      body: servers.isEmpty
          ? Center(child: Text(l10n.rememberedNone))
          : ListView(
              children: [
                for (final server in servers) ...[
                  SectionHeader(server.key),
                  for (final config in server.value.values)
                    ContextMenuRow(
                      semanticsLabel:
                          '${_displayName(l10n, config)}, ${_summary(l10n, config)}',
                      actions: [
                        RowAction(l10n.commonForget, () {
                          notifier.remove(server.key, config.key);
                          final text = l10n.rememberedForgotten(
                            _displayName(l10n, config),
                          );
                          ScaffoldMessenger.of(context).showUndo(
                            text,
                            undoLabel: l10n.commonUndo,
                            onUndo: () => notifier.upsert(server.key, config),
                          );
                          ref.read(announcerProvider).announceShown(text);
                        }),
                      ],
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(_displayName(l10n, config)),
                        subtitle: Text(_summary(l10n, config)),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
