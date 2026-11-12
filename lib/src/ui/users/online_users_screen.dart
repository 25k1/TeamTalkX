import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/chat/pm_providers.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/files/sort.dart';
import '../../app/users/user_selection_providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/accessible_widgets.dart';
import '../a11y/context_menu_row.dart';
import '../common/labels.dart';
import '../common/list_search_field.dart';
import 'user_row_actions.dart';
import 'user_selection_panel.dart';

enum UserSortField {
  nickname,
  id;

  String label(AppLocalizations l10n) => switch (this) {
    nickname => l10n.usersSortNickname,
    id => l10n.usersSortId,
  };
}

final userSortProvider =
    NotifierProvider<UserSortNotifier, SortState<UserSortField>>(
      UserSortNotifier.new,
    );

class UserSortNotifier extends SortNotifier<UserSortField> {
  @override
  UserSortField get defaultField => UserSortField.nickname;
}

Future<void> _showUserSort(BuildContext context, WidgetRef ref) =>
    showSortFor<UserSortField>(
      context,
      title: context.l10n.usersSortTitle,
      fields: UserSortField.values,
      labelOf: (f) => f.label(context.l10n),
      current: ref.read(userSortProvider),
      notifier: ref.read(userSortProvider.notifier),
      announce: ref.read(announcerProvider).announce,
    );

class OnlineUsersScreen extends ConsumerStatefulWidget {
  const OnlineUsersScreen({super.key});

  @override
  ConsumerState<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends ConsumerState<OnlineUsersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    ref.watch(serverStateTickProvider);
    final client = ref.watch(teamTalkClientProvider);
    final state = client.state;
    final selectionCount = ref.watch(userSelectionProvider).length;
    final sort = ref.watch(userSortProvider);
    final users =
        [
          for (final u in state.users.values)
            if (matchesSearch(_query, [u.nickname, u.username])) u,
        ]..sort((a, b) {
          final ordered = switch (sort.field) {
            UserSortField.nickname => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
            UserSortField.id => a.id.compareTo(b.id),
          };
          return sort.ascending ? ordered : -ordered;
        });

    final l10n = context.l10n;
    final sortText = sortLabel(l10n, sort, (f) => f.label(l10n));

    final list = Column(
      children: [
        ListSearchField(
          label: l10n.usersSearch,
          onChanged: (q) => setState(() => _query = q),
        ),
        Expanded(
          child: users.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? l10n.usersNobodyOnline
                        : l10n.searchNoMatch(_query),
                  ),
                )
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) =>
                      _OnlineUserTile(user: users[index]),
                ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.usersOnlineCount(state.users.length)),
        actions: [
          AccessibleIconButton(
            icon: Icons.sort,
            label: sortText,
            onPressed: () => _showUserSort(context, ref),
          ),
        ],
      ),
      body: selectionCount == 0
          ? list
          : Column(
              children: [
                UserSelectionPanel(count: selectionCount),
                Expanded(child: list),
              ],
            ),
    );
  }
}

class _OnlineUserTile extends ConsumerWidget {
  const _OnlineUserTile({required this.user});

  final TtUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.read(teamTalkClientProvider);
    final a = UserRowActions(context, ref, user);
    final channelPath = user.channelId > 0
        ? client.channelPath(user.channelId)
        : '';

    final unread = ref.watch(pmUnreadProvider(user.id));
    final semanticParts = [
      a.label,
      if (unread > 0) context.l10n.pmUnreadCount(unread),
      if (a.selectionMode && a.selected) context.l10n.commonSelected,
      channelPath.isEmpty
          ? context.l10n.usersNotInChannel
          : context.l10n.usersInChannel(channelPath),
    ];

    return ContextMenuRow(
      semanticsLabel: semanticParts.join(', '),
      selected: a.selectionMode ? a.selected : null,
      onTap: a.onTap,
      onLongPress: a.onLongPress,
      menuTitle: a.menuTitle,
      actions: a.actions,
      child: ListTile(
        leading: a.selectionMode
            ? Icon(
                a.selected ? Icons.check_circle : Icons.radio_button_unchecked,
              )
            : const Icon(Icons.person),
        title: Text(a.label),
        subtitle: Text(
          channelPath.isEmpty
              ? context.l10n.usersNotInChannelTitle
              : channelPath,
        ),
        selected: a.selected,
      ),
    );
  }
}
