import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../app/connection/server_list_loader.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../a11y/context_menu_row.dart';
import '../common/async_list_view.dart';
import '../common/list_search_field.dart';
import '../common/ui.dart';

String _banTypeLabel(AppLocalizations l10n, int types) {
  final parts = [
    if (types & BanTypes.username != 0) l10n.commonUsername,
    if (types & BanTypes.ipAddress != 0) l10n.bansSortIp,
    if (types & BanTypes.channel != 0) l10n.commonChannel,
  ];
  return parts.join(', ');
}

class BannedUsersScreen extends ConsumerStatefulWidget {
  const BannedUsersScreen({
    super.key,
    this.channelId = 0,
    this.channelName = '',
  });

  final int channelId;

  final String channelName;

  @override
  ConsumerState<BannedUsersScreen> createState() => _BannedUsersScreenState();
}

class _BannedUsersScreenState extends ConsumerState<BannedUsersScreen>
    with ServerListLoader<TtBannedUser, BannedUsersScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() => loadList(
    command: () =>
        ref.read(teamTalkClientProvider).listBans(channelId: widget.channelId),
    match: (event) => event is BannedUserEvent ? event.ban : null,
  );

  Future<void> _unban(TtBannedUser ban) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(teamTalkClientProvider).unbanUser(ban);
      setState(() => items.remove(ban));
      messenger.showMessage(
        ref.read(appLocalizationsProvider).bansUnbanned(ban.displayName),
      );
    } on Object catch (e, st) {
      appLog.w('users', 'Unban failed', e, st);
      reportFailure(ref, messenger, action: (l) => l.actionUnban, error: e);
    }
  }

  Future<void> _addBan() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => const _AddBanDialog(),
    );
    if (result == null) return;
    final (banType, value) = result;
    if (value.trim().isEmpty) return;
    try {
      await ref
          .read(teamTalkClientProvider)
          .addBan(
            ipAddress: banType == BanTypes.ipAddress ? value.trim() : '',
            username: banType == BanTypes.username ? value.trim() : '',
            banTypes: banType,
          );
      messenger.showMessage(
        ref.read(appLocalizationsProvider).bansBanned(value),
      );
      await _refresh();
    } on Object catch (e, st) {
      appLog.w('users', 'Ban failed', e, st);
      reportFailure(ref, messenger, action: (l) => l.actionBan, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelScoped = widget.channelId != 0;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          channelScoped
              ? l10n.bansTitleChannel(widget.channelName)
              : l10n.channelBannedUsers,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.commonRefresh,
            onPressed: loading ? null : _refresh,
          ),
        ],
      ),
      floatingActionButton: channelScoped
          ? null
          : FloatingActionButton(
              tooltip: l10n.bansAdd,
              onPressed: _addBan,
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          ListSearchField(
            label: l10n.bansSearch,
            onChanged: (q) => setState(() => _query = q),
          ),
          Expanded(
            child: AsyncListView<TtBannedUser>(
              loading: loading,
              failure: failure,
              items: [
                for (final b in items)
                  if (matchesSearch(_query, [
                    b.nickname,
                    b.username,
                    b.ipAddress,
                    b.channelPath,
                  ]))
                    b,
              ],
              loadingLabel: l10n.bansLoading,
              errorPrefix: l10n.bansLoadFailed,
              emptyMessage: _query.isEmpty
                  ? l10n.bansNone
                  : l10n.searchNoMatch(_query),
              itemBuilder: (context, ban) {
                final details = [
                  if (_banTypeLabel(l10n, ban.banTypes).isNotEmpty)
                    _banTypeLabel(l10n, ban.banTypes),
                  if (ban.ipAddress.isNotEmpty) ban.ipAddress,
                  if (ban.banTime.isNotEmpty) ban.banTime,
                  if (ban.channelPath.isNotEmpty) ban.channelPath,
                ].join(', ');
                return ContextMenuRow(
                  semanticsLabel: [
                    l10n.bansItemLabel(ban.displayName),
                    if (details.isNotEmpty) details,
                  ].join(', '),
                  actions: [RowAction(l10n.bansUnban, () => _unban(ban))],
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(ban.displayName),
                    subtitle: details.isEmpty ? null : Text(details),
                    trailing: IconButton(
                      icon: const Icon(Icons.undo),
                      tooltip: l10n.bansUnban,
                      onPressed: () => _unban(ban),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBanDialog extends StatefulWidget {
  const _AddBanDialog();

  @override
  State<_AddBanDialog> createState() => _AddBanDialogState();
}

class _AddBanDialogState extends State<_AddBanDialog> {
  int _banType = BanTypes.ipAddress;
  final _value = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isIp = _banType == BanTypes.ipAddress;
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.bansAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioGroup<int>(
            groupValue: _banType,
            onChanged: (value) {
              if (value != null) setState(() => _banType = value);
            },
            child: Column(
              children: [
                RadioListTile<int>(
                  title: Text(l10n.bansBanIp),
                  value: BanTypes.ipAddress,
                ),
                RadioListTile<int>(
                  title: Text(l10n.bansBanUsername),
                  value: BanTypes.username,
                ),
              ],
            ),
          ),
          TextField(
            controller: _value,
            autofocus: true,
            decoration: InputDecoration(
              labelText: isIp ? l10n.bansIpAddress : l10n.commonUsername,
            ),
            onSubmitted: (_) =>
                Navigator.of(context).pop((_banType, _value.text)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((_banType, _value.text)),
          child: Text(l10n.userBan),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }
}
