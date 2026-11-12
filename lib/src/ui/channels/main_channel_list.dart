part of 'main_screen.dart';

class _ChannelsView extends ConsumerWidget {
  const _ChannelsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serverStateTickProvider);
    final entries = ref.watch(channelTreeProvider);
    final selectionCount = ref.watch(userSelectionProvider).length;
    final list = entries.isEmpty
        ? Center(child: Text(context.l10n.channelsNone))
        : ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) => switch (entries[index]) {
              final ChannelEntry entry => _ChannelTile(entry: entry),
              final UserEntry entry => _UserTile(entry: entry),
            },
          );
    if (selectionCount == 0) return list;
    return Column(
      children: [
        UserSelectionPanel(count: selectionCount),
        Expanded(child: list),
      ],
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.entry});

  final ChannelEntry entry;

  void _create(BuildContext context) {
    pushScreen(context, ChannelEditScreen.create(parentId: entry.channel.id));
  }

  void _edit(BuildContext context) {
    pushScreen(context, ChannelEditScreen.edit(channelId: entry.channel.id));
  }

  void _showInfo(BuildContext context) {
    pushScreen(context, ChannelInfoScreen(channelId: entry.channel.id));
  }

  void _showBans(BuildContext context, String name) {
    pushScreen(
      context,
      BannedUsersScreen(channelId: entry.channel.id, channelName: name),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.channelDeleteTitle(name),
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;
    await ref.runCommand(
      messenger,
      () => ref.read(teamTalkClientProvider).removeChannel(entry.channel.id),
      errorLabel: (l) => l.actionDelete,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = entry.channel;
    final l10n = context.l10n;
    final client = ref.watch(teamTalkClientProvider);
    final st = client.state;
    final serverName = st.serverInfo.name;
    final canMoveHere =
        ref.watch(userSelectionProvider).isNotEmpty &&
        (st.hasRight(UserRights.moveUsers) ||
            client.isChannelOperator(st.myUserId, channel.id));
    final isOperator = client.isChannelOperator(st.myUserId, channel.id);
    final everyoneMayTalk = channel.voiceUsers.contains(TtChannel.freeForAll);
    final canViewBans = st.hasRight(UserRights.banUsers) || isOperator;
    final name = channel.isRoot
        ? (serverName.isEmpty
              ? (channel.name.isEmpty ? '/' : channel.name)
              : serverName)
        : channel.name;
    final countText = entry.hasSubchannels
        ? (entry.totalUserCount > 0
              ? '${entry.userCount}/${entry.totalUserCount}'
              : null)
        : (entry.userCount > 0 ? '${entry.userCount}' : null);
    final semanticParts = [
      name,
      ?countText,
      if (channel.hasPassword) l10n.channelPasswordProtected,
      if (channel.isClassroom) l10n.channelTypeClassroom,
      if (isOperator) l10n.channelYouAreOperator,
      if (entry.isJoined) l10n.channelJoined,
      if (entry.isExpanded) l10n.channelExpanded,
    ];
    void toggleExpand() {
      final current = ref.read(effectiveExpandedChannelProvider);
      ref.read(expandedChannelProvider.notifier).toggle(channel.id, current);
    }

    return ContextMenuRow(
      semanticsLabel: semanticParts.join(', '),
      onTap: toggleExpand,
      menuTitle: name,
      actions: [
        if (!entry.isJoined)
          RowAction(
            l10n.commonJoin,
            () => joinChannelFlow(context, ref, channel),
            icon: Icons.login,
          ),
        if (canMoveHere)
          RowAction(
            l10n.channelMoveHere,
            () => moveSelectedUsers(context, ref, channel.id),
            icon: Icons.move_down,
          ),
        RowAction(
          l10n.channelInformation,
          () => _showInfo(context),
          icon: Icons.info_outline,
        ),
        if (isOperator)
          RowAction(
            l10n.operatorStop,
            () => stopBeingOperator(context, ref, channel),
            icon: Icons.remove_moderator,
          )
        else
          RowAction(
            l10n.operatorBecome,
            () => becomeOperator(context, ref, channel),
            icon: Icons.add_moderator,
          ),
        if (channel.isClassroom &&
            (isOperator || st.hasRight(UserRights.modifyChannels)))
          RowAction(
            everyoneMayTalk
                ? l10n.transmitOnlyAllowedTalk
                : l10n.transmitEveryoneTalks,
            () => setEveryoneMayTalk(
              context,
              ref,
              channel,
              everyone: !everyoneMayTalk,
            ),
            icon: Icons.groups,
          ),
        if (canViewBans)
          RowAction(
            l10n.channelBannedUsers,
            () => _showBans(context, name),
            icon: Icons.block,
          ),
        RowAction(
          l10n.channelCreateSub,
          () => _create(context),
          icon: Icons.add,
        ),
        RowAction(l10n.channelEdit, () => _edit(context), icon: Icons.edit),
        if (!channel.isRoot)
          RowAction(
            l10n.channelDelete,
            () => _delete(context, ref, name),
            icon: Icons.delete,
          ),
      ],
      child: ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + entry.depth * 16.0),
        leading: Icon(
          channel.hasPassword ? Icons.lock : Icons.tag,
          color: entry.isJoined ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          name,
          style: entry.isJoined
              ? const TextStyle(fontWeight: FontWeight.bold)
              : null,
        ),
        subtitle: (channel.topic.isEmpty && countText == null)
            ? null
            : Text(
                [
                  if (channel.topic.isNotEmpty) channel.topic,
                  ?countText,
                ].join(' · '),
              ),
        selected: entry.isJoined,
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.entry});

  final UserEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = entry.user;
    final a = UserRowActions(context, ref, user, includeMute: true);

    final unread = ref.watch(pmUnreadProvider(user.id));
    final semanticParts = [
      a.label,
      if (unread > 0) context.l10n.pmUnreadCount(unread),
      if (a.selectionMode && a.selected) context.l10n.commonSelected,
      if (user.isMutedLocally) context.l10n.userMutedTag,
    ];

    return ContextMenuRow(
      semanticsLabel: semanticParts.join(', '),
      selected: a.selectionMode ? a.selected : null,
      onTap: a.onTap,
      onLongPress: a.onLongPress,
      menuTitle: a.menuTitle,
      actions: a.actions,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: 16.0 + entry.depth * 16.0),
        leading: a.selectionMode
            ? Icon(
                a.selected ? Icons.check_circle : Icons.radio_button_unchecked,
              )
            : Icon(
                user.isTalking ? Icons.record_voice_over : Icons.person,
                color: user.isTalking ? Colors.green : null,
              ),
        title: Text(a.label),
        selected: a.selected,
      ),
    );
  }
}
