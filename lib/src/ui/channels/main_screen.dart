import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsRole;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/channels/channel_tree_providers.dart';
import '../../app/chat/chat_providers.dart';
import '../../app/chat/pm_providers.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/connection/foreground_notification.dart';
import '../../app/recording/recording_controller.dart';
import '../../app/settings/event_feedback.dart';
import '../../app/settings/locale_providers.dart';
import '../../app/settings/settings_providers.dart';
import '../../app/users/user_config.dart';
import '../../app/users/user_selection_providers.dart';
import '../../app/voice/hardware_controls.dart';
import '../../app/voice/media_stream_providers.dart';
import '../../app/voice/voice_providers.dart';
import '../../app/voice/volume_controller.dart';
import '../../diagnostics/log.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/failure_messages.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/accessible_widgets.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import '../chat/chat_screen.dart';
import '../common/command_runner.dart';
import '../common/failure_report.dart';
import '../common/labels.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';
import '../connection/nickname_action.dart';
import '../files/files_screen.dart';
import '../servers/server_properties_screen.dart';
import '../servers/server_statistics_screen.dart';
import '../settings/settings_screen.dart';
import '../users/banned_users_screen.dart';
import '../users/online_users_screen.dart';
import '../users/user_accounts_screen.dart';
import '../users/user_row_actions.dart';
import '../users/user_selection_panel.dart';
import '../voice/audio_settings_screen.dart';
import 'channel_edit_screen.dart';
import 'channel_info_screen.dart';
import 'channel_rights_actions.dart';
import 'media_stream_screen.dart';

part 'main_channel_list.dart';
part 'main_controls.dart';
part 'main_navigation.dart';

Future<void> pickChannelSort(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final sort = await showSingleChoiceMenu<ChannelSort>(
    context,
    title: l10n.channelsSortTitle,
    options: {for (final s in ChannelSort.values) s: s.label(l10n)},
    selected: ref.read(channelSortProvider),
  );
  if (sort == null) return;
  ref.read(channelSortProvider.notifier).set(sort);
  ref.read(announcerProvider).announce(l10n.channelsSortedBy(sort.label(l10n)));
}

Future<void> joinChannelFlow(
  BuildContext context,
  WidgetRef ref,
  TtChannel channel,
) async {
  var password = '';
  if (channel.hasPassword) {
    final l10n = context.l10n;
    final entered = await promptText(
      context,
      title: l10n.channelPasswordTitle,
      label: l10n.commonPassword,
      obscureText: true,
      submitLabel: l10n.commonJoin,
    );
    if (entered == null) return;
    password = entered;
  }
  try {
    await ref
        .read(connectionProvider.notifier)
        .joinChannel(channel.id, password: password);
  } on Object catch (e, st) {
    appLog.w('channels', 'Joining channel ${channel.id} failed', e, st);
    if (context.mounted) {
      reportFailure(
        ref,
        ScaffoldMessenger.of(context),
        action: (l) => l.actionJoinChannel,
        error: e,
      );
    } else {
      ref
          .read(announcerProvider)
          .announce(ref.read(appLocalizationsProvider).actionJoinChannel);
    }
  }
}

Future<void> handleMoreAction(
  BuildContext context,
  WidgetRef ref,
  String action,
) async {
  final client = ref.read(teamTalkClientProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  switch (action) {
    case 'online':
      pushScreen(context, const OnlineUsersScreen());
    case 'record':
      await ref.read(recordingProvider.notifier).toggle();
    case 'status':
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _StatusDialog(),
      );
    case 'nickname':
      await editNickname(context, ref);
    case 'broadcast':
      final text = await promptText(
        context,
        title: l10n.broadcastTitle,
        label: l10n.broadcastLabel,
        capitalization: TextCapitalization.sentences,
        submitLabel: l10n.commonSend,
      );
      if (text == null || text.trim().isEmpty) return;
      await ref.runCommand(
        messenger,
        () => client.sendBroadcastMessage(text.trim()),
        announce: (l) => l.broadcastSent,
        errorLabel: (l) => l.actionBroadcast,
      );
    case 'bans':
      pushScreen(context, const BannedUsersScreen());
    case 'accounts':
      pushScreen(context, const UserAccountsScreen());
    case 'serverprops':
      pushScreen(context, const ServerPropertiesScreen());
    case 'serverstats':
      pushScreen(context, const ServerStatisticsScreen());
    case 'stream':
      final file = await openFile();
      if (file == null) return;
      final failure = await ref
          .read(mediaStreamProvider.notifier)
          .start(file.path, file.name);
      if (failure != null) {
        messenger.showMessage(l10n.failureMessage(failure));
      } else if (context.mounted) {
        pushScreen(context, const MediaStreamScreen());
      }
    case 'mediastream':
      pushScreen(context, const MediaStreamScreen());
    case 'stopstream':
      ref.read(mediaStreamProvider.notifier).stop();
    case 'settings':
      pushScreen(context, const SettingsScreen());
  }
}

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _tabIndex = 0;
  DateTime? _backPressedAt;

  static const backAgainWindow = Duration(seconds: 3);

  @override
  Widget build(BuildContext context) {
    ref.watch(eventFeedbackProvider);
    ref.watch(hardwareControlsProvider);
    ref.watch(userConfigApplyProvider);
    ref.watch(volumeControllerProvider);
    ref.watch(foregroundNotificationProvider);
    ref.watch(serverStateTickProvider);
    final client = ref.watch(teamTalkClientProvider);
    final serverName = client.state.serverInfo.name;

    final l10n = context.l10n;
    final joined = client.state.channels[client.state.joinedChannelId];
    final inRoot = joined == null || joined.isRoot;
    final motd = client.state.serverInfo.motd;
    final titleName = inRoot
        ? (serverName.isEmpty ? l10n.channelsTitle : serverName)
        : joined.name;
    final showMotd = inRoot && motd.isNotEmpty;

    final speakerMuted = ref.watch(speakerMutedProvider);
    String muteLabel() =>
        speakerMuted ? l10n.mainUnmuteServer : l10n.mainMuteServer;
    void toggleMute() => ref.read(voiceProvider.notifier).toggleSpeakerMute();
    void disconnect() => ref.read(connectionProvider.notifier).disconnect();
    final recording = ref.watch(recordingProvider) is RecordingActive;
    String recordLabel() =>
        recording ? l10n.recordingStop : l10n.recordingStart;
    void toggleRecording() =>
        unawaited(ref.read(recordingProvider.notifier).toggle());

    Future<void> showTitleMenu() async {
      final action = await showAccessibleMenu<String>(
        context,
        title: titleName,
        items: [
          MenuItemSpec(
            'mute',
            muteLabel(),
            icon: speakerMuted ? Icons.volume_up : Icons.volume_off,
          ),
          MenuItemSpec(
            'record',
            recordLabel(),
            icon: recording ? Icons.stop_circle : Icons.fiber_manual_record,
          ),
          MenuItemSpec('disconnect', l10n.commonDisconnect, icon: Icons.logout),
        ],
      );
      if (!context.mounted || action == null) return;
      switch (action) {
        case 'mute':
          toggleMute();
        case 'record':
          toggleRecording();
        case 'disconnect':
          disconnect();
      }
    }

    final expandedId = ref.watch(effectiveExpandedChannelProvider);
    final expandedChannel =
        expandedId > 0 && expandedId != client.state.joinedChannelId
        ? client.state.channels[expandedId]
        : null;

    ref.listen(connectionProvider, (previous, next) {
      if (next is Disconnected) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tabIndex != 0) {
          setState(() => _tabIndex = 0);
          return;
        }
        final now = DateTime.now();
        final first = _backPressedAt;
        final twice = ref
            .read(connectionSettingsProvider)
            .backTwiceToDisconnect;
        if (!twice ||
            (first != null && now.difference(first) < backAgainWindow)) {
          _backPressedAt = null;
          unawaited(ref.read(connectionProvider.notifier).disconnect());
          return;
        }
        _backPressedAt = now;
        ScaffoldMessenger.of(
          context,
        ).showMessage(l10n.mainBackAgainToDisconnect);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Semantics(
            key: ValueKey((speakerMuted, recording)),
            header: true,
            label: showMotd ? '$titleName, $motd' : titleName,
            excludeSemantics: true,
            onLongPress: showTitleMenu,
            customSemanticsActions: {
              CustomSemanticsAction(label: muteLabel()): toggleMute,
              CustomSemanticsAction(label: recordLabel()): toggleRecording,
              CustomSemanticsAction(label: l10n.commonDisconnect): disconnect,
            },
            child: InkWell(
              onLongPress: showTitleMenu,
              excludeFromSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: kMinInteractiveDimension,
                  minHeight: kMinInteractiveDimension,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  child: showMotd
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(titleName),
                            Text(
                              motd,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        )
                      : Text(titleName),
                ),
              ),
            ),
          ),
          actions: [
            if (recording)
              Tooltip(
                message: l10n.recordingIndicator,
                child: Icon(
                  Icons.fiber_manual_record,
                  color: Theme.of(context).colorScheme.error,
                  semanticLabel: l10n.recordingIndicator,
                ),
              ),
            if (_tabIndex == 0)
              AccessibleIconButton(
                icon: Icons.sort,
                label: l10n.channelsSortBy(
                  ref.watch(channelSortProvider).label(l10n),
                ),
                onPressed: () => pickChannelSort(context, ref),
              ),
            if (_tabIndex == 0 && expandedChannel != null)
              IconButton(
                icon: const Icon(Icons.login),
                tooltip: l10n.mainJoinChannel(expandedChannel.name),
                onPressed: () => joinChannelFlow(context, ref, expandedChannel),
              ),
          ],
        ),
        drawer: const _MainDrawer(),
        body: IndexedStack(
          index: _tabIndex,
          children: [
            const _ChannelsView(),
            ChatView(active: _tabIndex == 1),
            const FilesView(),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _VoiceControlsBar(),
            _MainTabBar(
              selectedIndex: _tabIndex,
              onSelected: (index) => setState(() => _tabIndex = index),
            ),
          ],
        ),
      ),
    );
  }
}
