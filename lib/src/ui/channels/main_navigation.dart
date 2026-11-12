part of 'main_screen.dart';

class _MainDrawer extends ConsumerWidget {
  const _MainDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final client = ref.watch(teamTalkClientProvider);
    final streaming = ref.watch(mediaStreamProvider) != null;
    final recording = ref.watch(recordingProvider) is RecordingActive;
    final state = client.state;
    final serverName = state.serverInfo.name;
    final nickname = state.users[state.myUserId]?.nickname ?? '';
    final scheme = Theme.of(context).colorScheme;

    void go(String action) {
      Navigator.of(context).pop();
      unawaited(handleMoreAction(context, ref, action));
    }

    Widget item(IconData icon, String label, String action) => Semantics(
      label: label,
      button: false,
      excludeSemantics: true,
      onTap: () => go(action),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: () => go(action),
      ),
    );

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.paddingOf(context).top + 160,
            ),
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + 16,
              16,
              8,
            ),
            color: scheme.primaryContainer,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              heightFactor: 1,
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      serverName.isEmpty ? l10n.appTitle : serverName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (nickname.isNotEmpty)
                      Text(l10n.navConnectedAs(nickname)),
                  ],
                ),
              ),
            ),
          ),
          item(Icons.people, l10n.navOnlineUsers, 'online'),
          item(Icons.person_pin, l10n.statusChange, 'status'),
          item(Icons.badge, l10n.navChangeNickname, 'nickname'),
          if (state.hasRight(UserRights.textMessageBroadcast))
            item(Icons.campaign, l10n.navSendBroadcast, 'broadcast'),
          if (state.hasRight(UserRights.banUsers))
            item(Icons.block, l10n.channelBannedUsers, 'bans'),
          if (client.isAdmin)
            item(Icons.manage_accounts, l10n.navUserAccounts, 'accounts'),
          item(Icons.dns, l10n.navServerProperties, 'serverprops'),
          if (client.isAdmin)
            item(Icons.query_stats, l10n.statsTitle, 'serverstats'),
          if (streaming) ...[
            item(Icons.graphic_eq, l10n.navMediaStream, 'mediastream'),
            item(Icons.stop, l10n.navStopStreaming, 'stopstream'),
          ] else if (state.joinedChannelId > 0 &&
              state.hasRight(UserRights.transmitMediaFileAudio))
            item(Icons.play_circle, l10n.navStreamMediaFile, 'stream'),
          if (recording)
            item(Icons.stop_circle, l10n.recordingStop, 'record')
          else if (state.joinedChannelId > 0)
            item(Icons.fiber_manual_record, l10n.recordingStart, 'record'),
          const Divider(),
          item(Icons.settings, l10n.commonSettings, 'settings'),
        ],
      ),
    );
  }
}

class _MainTabBar extends ConsumerWidget {
  const _MainTabBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _tabIcons = [Icons.tag, Icons.chat, Icons.folder];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final unread = ref.watch(channelChatUnreadProvider);
    final tabs = [
      (_tabIcons[0], l10n.channelsTitle),
      (_tabIcons[1], unread > 0 ? l10n.tabChatUnread(unread) : l10n.tabChat),
      (_tabIcons[2], l10n.tabFiles),
    ];
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Semantics(
          role: SemanticsRole.tabBar,
          explicitChildNodes: true,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: Semantics(
                    role: SemanticsRole.tab,
                    label: l10n.tabPosition(tabs[i].$2, i + 1, tabs.length),
                    selected: i == selectedIndex,
                    excludeSemantics: true,
                    onTap: () => onSelected(i),
                    child: InkWell(
                      onTap: () => onSelected(i),
                      excludeFromSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tabs[i].$1,
                              color: i == selectedIndex
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            Text(
                              tabs[i].$2,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: i == selectedIndex
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: i == selectedIndex
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
