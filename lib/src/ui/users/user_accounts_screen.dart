import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/connection/server_list_loader.dart';
import '../../app/files/sort.dart';
import '../../app/servers/bearware_login.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/accessible_widgets.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import '../common/async_list_view.dart';
import '../common/labels.dart';
import '../common/list_search_field.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';
import '../common/unsaved_changes.dart';
import '../settings/settings_widgets.dart';

part 'user_account_edit_screen.dart';

enum UserAccountSortField {
  username,
  userType,
  channel,
  lastModified,
  lastLogin;

  String label(AppLocalizations l10n) => switch (this) {
    username => l10n.commonUsername,
    userType => l10n.accountsSortUserType,
    channel => l10n.commonChannel,
    lastModified => l10n.accountsSortLastEdited,
    lastLogin => l10n.accountsSortLastLogin,
  };
}

final userAccountSortProvider =
    NotifierProvider<UserAccountSortNotifier, SortState<UserAccountSortField>>(
      UserAccountSortNotifier.new,
    );

class UserAccountSortNotifier extends SortNotifier<UserAccountSortField> {
  @override
  UserAccountSortField get defaultField => UserAccountSortField.username;
}

class UserAccountsScreen extends ConsumerStatefulWidget {
  const UserAccountsScreen({super.key});

  @override
  ConsumerState<UserAccountsScreen> createState() => _UserAccountsScreenState();
}

class _UserAccountsScreenState extends ConsumerState<UserAccountsScreen>
    with ServerListLoader<TtUserAccount, UserAccountsScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() => loadList(
    command: () => ref.read(teamTalkClientProvider).listUserAccounts(),
    match: (event) => event is UserAccountEvent ? event.account : null,
  );

  Future<void> _edit([TtUserAccount? account]) async {
    final saved = await pushScreenForResult<bool>(
      context,
      UserAccountEditScreen(account: account),
    );
    if (saved ?? false) await _refresh();
  }

  Future<void> _delete(TtUserAccount account) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.accountsDeleteTitle(account.username),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(teamTalkClientProvider)
          .deleteUserAccount(account.username);
      setState(() => items.remove(account));
      messenger.showMessage(l10n.accountsDeleted(account.username));
    } on Object catch (e, st) {
      appLog.w('users', 'Deleting user account failed', e, st);
      reportFailure(ref, messenger, action: (l) => l.actionDelete, error: e);
    }
  }

  Future<void> _showSort() => showSortFor<UserAccountSortField>(
    context,
    title: context.l10n.accountsSortTitle,
    fields: UserAccountSortField.values,
    labelOf: (f) => f.label(context.l10n),
    current: ref.read(userAccountSortProvider),
    notifier: ref.read(userAccountSortProvider.notifier),
    announce: ref.read(announcerProvider).announce,
  );

  List<TtUserAccount> _sorted(SortState<UserAccountSortField> sort) {
    int compare(TtUserAccount a, TtUserAccount b) => switch (sort.field) {
      UserAccountSortField.username => a.username.toLowerCase().compareTo(
        b.username.toLowerCase(),
      ),
      UserAccountSortField.userType => a.userType.compareTo(b.userType),
      UserAccountSortField.channel => a.initChannel.toLowerCase().compareTo(
        b.initChannel.toLowerCase(),
      ),
      UserAccountSortField.lastModified => a.lastModified.compareTo(
        b.lastModified,
      ),
      UserAccountSortField.lastLogin => a.lastLogin.compareTo(b.lastLogin),
    };
    return [...items]
      ..sort((a, b) => sort.ascending ? compare(a, b) : -compare(a, b));
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(userAccountSortProvider);
    final accounts = [
      for (final a in _sorted(sort))
        if (matchesSearch(_query, [a.username, a.note])) a,
    ];
    final l10n = context.l10n;
    final sortText = sortLabel(l10n, sort, (f) => f.label(l10n));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accountsTitle),
        actions: [
          AccessibleIconButton(
            icon: Icons.sort,
            label: sortText,
            onPressed: _showSort,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.commonRefresh,
            onPressed: loading ? null : _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.accountsAdd,
        onPressed: _edit,
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          ListSearchField(
            label: l10n.accountsSearch,
            onChanged: (q) => setState(() => _query = q),
          ),
          Expanded(
            child: AsyncListView<TtUserAccount>(
              loading: loading,
              failure: failure,
              items: accounts,
              loadingLabel: l10n.accountsLoading,
              errorPrefix: l10n.accountsLoadFailed,
              emptyMessage: _query.isEmpty
                  ? l10n.accountsNone
                  : l10n.searchNoMatch(_query),
              itemBuilder: (context, account) {
                final name = account.username.isEmpty
                    ? l10n.accountsAnonymous
                    : account.username;
                final subtitle = [
                  account.isAdmin
                      ? l10n.accountTypeAdmin
                      : l10n.accountTypeDefault,
                  if (account.note.isNotEmpty) account.note,
                ].join(' ');
                return ContextMenuRow(
                  semanticsLabel: '$name, $subtitle',
                  onTap: () => _edit(account),
                  actions: [
                    RowAction(
                      l10n.commonEdit,
                      () => _edit(account),
                      icon: Icons.edit,
                    ),
                    RowAction(
                      l10n.commonDelete,
                      () => _delete(account),
                      icon: Icons.delete,
                    ),
                  ],
                  child: ListTile(
                    leading: Icon(
                      account.isAdmin
                          ? Icons.admin_panel_settings
                          : Icons.person,
                    ),
                    title: Text(name),
                    subtitle: Text(subtitle),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: l10n.commonDelete,
                      onPressed: () => _delete(account),
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
