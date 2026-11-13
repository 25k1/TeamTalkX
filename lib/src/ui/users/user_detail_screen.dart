import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/settings/locale_providers.dart';
import '../../app/settings/settings_providers.dart';
import '../../app/users/user_config.dart';
import '../../diagnostics/log.dart';
import '../../domain/models.dart';
import '../../domain/sound_level.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../chat/pm_screen.dart';
import '../common/command_runner.dart';
import '../common/ui.dart';
import '../settings/settings_widgets.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  late int _volumePercent;
  late bool _muted;
  late int _mediaVolumePercent;
  late bool _mediaMuted;
  late int _subscriptions;
  bool _perClient = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(teamTalkClientProvider);
    _volumePercent = volumeToPercent(client.getUserVolume(widget.userId));
    _muted = client.isUserMuted(widget.userId);
    _mediaVolumePercent = volumeToPercent(
      client.getUserVolume(widget.userId, media: true),
    );
    _mediaMuted = client.isUserMuted(widget.userId, media: true);
    final user = client.state.users[widget.userId];
    _subscriptions = user?.localSubscriptions ?? 0;
    final serverKey = ref.read(connectionProvider.notifier).currentServerKey;
    if (serverKey != null && user != null && user.clientName.isNotEmpty) {
      final byUser = ref.read(userConfigsProvider)[serverKey];
      _perClient =
          byUser?.containsKey('${_usernameFor(user)} ${user.clientName}') ??
          false;
    }
  }

  String _usernameFor(TtUser user) => effectiveUsername(
    user,
    myUserId: ref.read(teamTalkClientProvider).myUserId,
    loginUsername: ref.read(connectionProvider.notifier).currentEntry?.username,
  );

  void _saveConfig() {
    final client = ref.read(teamTalkClientProvider);
    final serverKey = ref.read(connectionProvider.notifier).currentServerKey;
    final user = client.state.users[widget.userId];
    if (serverKey == null || user == null) return;
    final username = _usernameFor(user);
    if (username.isEmpty) return;
    final notifier = ref.read(userConfigsProvider.notifier);
    final config = StoredUserConfig(
      username: username,
      clientName: _perClient ? user.clientName : '',
      muted: _muted,
      volumePercent: _volumePercent,
      mediaMuted: _mediaMuted,
      mediaVolumePercent: _mediaVolumePercent,
      subscriptions:
          _subscriptions & (kManagedSubscriptions | kInterceptSubscriptions),
    );
    final altClient = _perClient ? '' : user.clientName;
    final altKey = altClient.isEmpty ? username : '$username $altClient';
    if (altKey != config.key) notifier.remove(serverKey, altKey);
    notifier.upsert(serverKey, config);
  }

  void _forget() {
    final client = ref.read(teamTalkClientProvider);
    final serverKey = ref.read(connectionProvider.notifier).currentServerKey;
    final user = client.state.users[widget.userId];
    if (serverKey == null || user == null) return;
    final notifier = ref.read(userConfigsProvider.notifier);
    final username = _usernameFor(user);
    notifier.remove(serverKey, username);
    if (user.clientName.isNotEmpty) {
      notifier.remove(serverKey, '$username ${user.clientName}');
    }
    ref
        .read(announcerProvider)
        .announce(ref.read(appLocalizationsProvider).userForgotSettings);
  }

  Future<void> _toggleSubscription(TtUser user, int mask, bool value) async {
    final client = ref.read(teamTalkClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(
      () => _subscriptions = value
          ? _subscriptions | mask
          : _subscriptions & ~mask,
    );
    try {
      if (value) {
        await client.subscribe(user.id, mask);
      } else {
        await client.unsubscribe(user.id, mask);
      }
      client.refreshUser(user.id);
      _saveConfig();
    } on Object catch (e, st) {
      appLog.w(
        'users',
        'Subscription change for user ${user.id} failed',
        e,
        st,
      );
      setState(
        () => _subscriptions = value
            ? _subscriptions & ~mask
            : _subscriptions | mask,
      );
      reportFailure(
        ref,
        messenger,
        action: (l) => l.actionChangeSubscription,
        error: e,
      );
    }
  }

  Future<void> _runCommand(
    Future<void> Function() command, {
    required L10nText announce,
    required L10nText errorLabel,
  }) => ref.runCommand(
    ScaffoldMessenger.of(context),
    command,
    announce: announce,
    errorLabel: errorLabel,
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(serverStateTickProvider);
    final client = ref.watch(teamTalkClientProvider);
    final state = client.state;
    final user = state.users[widget.userId];
    final l10n = context.l10n;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.userTitle)),
        body: Center(child: Text(l10n.userNoLongerOnline)),
      );
    }

    final myChannelId = state.joinedChannelId;
    final canMove =
        state.hasRight(UserRights.moveUsers) &&
        myChannelId > 0 &&
        user.channelId != myChannelId;

    Widget subscription(String label, int mask) => SwitchListTile(
      title: Text(label),
      value: (_subscriptions & mask) != 0,
      onChanged: (value) => _toggleSubscription(user, mask, value),
    );

    Widget volumeSlider(String label, int value, ValueChanged<int> apply) =>
        LevelSlider(
          label: label,
          value: value,
          max: volumePercentMax,
          percent: true,
          step: 5,
          onChanged: apply,
          onChangeEnd: (_) => _saveConfig(),
        );

    return Scaffold(
      appBar: AppBar(title: Text(user.displayName)),
      body: ListView(
        children: [
          if (user.statusMessage.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.userStatus),
              subtitle: Text(user.statusMessage),
            ),
          if (user.clientName.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.devices),
              title: Text(l10n.userClient),
              subtitle: Text(user.clientName),
            ),
          ListTile(
            leading: const Icon(Icons.message),
            title: Text(l10n.userSendPrivateMessage),
            onTap: () => pushScreen(context, PmScreen(userId: user.id)),
          ),
          const Divider(),
          volumeSlider(l10n.userVoiceVolume, _volumePercent, (v) {
            setState(() => _volumePercent = v);
            client.setUserVolume(user.id, volumeFromPercent(v));
          }),
          SwitchListTile(
            title: Text(l10n.userMuteVoice),
            value: _muted,
            onChanged: (value) {
              setState(() => _muted = value);
              client.setUserMute(user.id, muted: value);
              ref
                  .read(announcerProvider)
                  .announce(value ? l10n.commonMuted : l10n.commonUnmuted);
              _saveConfig();
            },
          ),
          volumeSlider(l10n.userMediaVolume, _mediaVolumePercent, (v) {
            setState(() => _mediaVolumePercent = v);
            client.setUserVolume(user.id, volumeFromPercent(v), media: true);
          }),
          _EffectiveVolumeRow(mediaVolumePercent: _mediaVolumePercent),
          SwitchListTile(
            title: Text(l10n.userMuteMedia),
            value: _mediaMuted,
            onChanged: (value) {
              setState(() => _mediaMuted = value);
              client.setUserMute(user.id, muted: value, media: true);
              ref
                  .read(announcerProvider)
                  .announce(
                    value ? l10n.userMediaMuted : l10n.userMediaUnmuted,
                  );
              _saveConfig();
            },
          ),
          const Divider(),
          SectionHeader(l10n.userSubscriptions),
          subscription(l10n.userSubVoice, Subscriptions.voice),
          subscription(l10n.userSubChannelMessages, Subscriptions.channelMsg),
          subscription(l10n.userSubPrivateMessages, Subscriptions.userMsg),
          subscription(l10n.userSubBroadcasts, Subscriptions.broadcastMsg),
          subscription(l10n.userSubCustom, Subscriptions.customMsg),
          subscription(l10n.userSubMediaFiles, Subscriptions.mediaFile),
          if (client.isAdmin) ...[
            const Divider(),
            SectionHeader(l10n.userIntercept),
            subscription(l10n.userInterceptVoice, Subscriptions.interceptVoice),
            subscription(
              l10n.userInterceptPrivate,
              Subscriptions.interceptUserMsg,
            ),
            subscription(
              l10n.userInterceptChannel,
              Subscriptions.interceptChannelMsg,
            ),
            subscription(
              l10n.userInterceptCustom,
              Subscriptions.interceptCustomMsg,
            ),
            subscription(
              l10n.userInterceptMedia,
              Subscriptions.interceptMediaFile,
            ),
          ],
          const Divider(),
          SectionHeader(l10n.userRememberedSettings),
          if (user.clientName.isNotEmpty)
            SwitchListTile(
              title: Text(l10n.userRememberForClient),
              subtitle: Text(
                l10n.userRememberMatch(
                  user.username.isEmpty
                      ? l10n.userRememberThisUser
                      : user.username,
                  user.clientName,
                ),
              ),
              value: _perClient,
              onChanged: (value) {
                setState(() => _perClient = value);
                _saveConfig();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.userForgetRemembered),
            onTap: _forget,
          ),
          if (canMove) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.move_down),
              title: Text(l10n.userMoveToMyChannel),
              onTap: () => _runCommand(
                () => client.moveUser(user.id, myChannelId),
                announce: (l) => l.userMoved(user.displayName),
                errorLabel: (l) => l.actionMoveUser,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EffectiveVolumeRow extends ConsumerWidget {
  const _EffectiveVolumeRow({required this.mediaVolumePercent});

  final int mediaVolumePercent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (master, media) = ref.watch(
      playbackSettingsProvider.select(
        (s) => (s.masterVolumePercent, s.mediaVolumePercent),
      ),
    );
    final effective =
        (mediaVolumePercent / 100) * (media / 100) * (master / 100);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        context.l10n.userEffectiveVolume((effective * 100).toStringAsFixed(0)),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
