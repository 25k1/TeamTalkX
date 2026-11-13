import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/chat/chat_history.dart';
import '../../app/settings/settings_providers.dart';
import '../../domain/chat_history.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import 'settings_widgets.dart';

class ChatHistoryScreen extends ConsumerStatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  ConsumerState<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends ConsumerState<ChatHistoryScreen> {
  static const _choices = [7, 30, 90, 365, 0];

  late Future<List<ChatServerSummary>> _servers = _load();

  Future<List<ChatServerSummary>> _load() =>
      ref.read(chatHistoryProvider).servers();

  void _reload() => setState(() => _servers = _load());

  String _keepLabel(AppLocalizations l10n, int days) =>
      days == 0 ? l10n.chatHistoryForever : l10n.chatHistoryDays(days);

  Future<void> _clear(ChatServerSummary server) async {
    final l10n = context.l10n;
    if (!await confirm(
      context,
      title: l10n.chatHistoryClearServerConfirm(server.name),
      confirmLabel: l10n.chatHistoryClear,
    )) {
      return;
    }
    await ref.read(chatHistoryProvider).clearServer(server.server);
    _reload();
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    if (!await confirm(
      context,
      title: l10n.chatHistoryClearAllConfirm,
      confirmLabel: l10n.chatHistoryClearAll,
    )) {
      return;
    }
    await ref.read(chatHistoryProvider).clearAll();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = ref.watch(
      chatSettingsProvider.select((s) => s.chatRetentionDays),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsChatHistory)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.chatHistoryKeep),
            subtitle: Text(_keepLabel(l10n, days)),
            onTap: () async {
              final choice = await showSingleChoiceMenu<int>(
                context,
                title: l10n.chatHistoryKeep,
                options: {for (final d in _choices) d: _keepLabel(l10n, d)},
                selected: days,
              );
              if (choice == null) return;
              ref
                  .read(chatSettingsProvider.notifier)
                  .setChatRetentionDays(choice);
              _reload();
            },
          ),
          SectionHeader(l10n.chatHistoryServers),
          FutureBuilder<List<ChatServerSummary>>(
            future: _servers,
            builder: (context, snapshot) {
              final servers = snapshot.data ?? const [];
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              if (servers.isEmpty) {
                return ListTile(title: Text(l10n.chatHistoryNone));
              }
              return Column(
                children: [
                  for (final server in servers)
                    ContextMenuRow(
                      semanticsLabel:
                          '${server.name}, ${l10n.chatHistoryMessages(server.messages)}',
                      onTap: () => _clear(server),
                      actions: [
                        RowAction(l10n.chatHistoryClear, () => _clear(server)),
                      ],
                      child: ListTile(
                        leading: const Icon(Icons.dns),
                        title: Text(server.name),
                        subtitle: Text(
                          '${server.server} · '
                          '${l10n.chatHistoryMessages(server.messages)}',
                        ),
                      ),
                    ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep),
                    title: Text(l10n.chatHistoryClearAll),
                    onTap: _clearAll,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
