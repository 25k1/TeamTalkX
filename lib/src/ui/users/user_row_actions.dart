import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/users/user_selection_providers.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../a11y/context_menu_row.dart';
import '../channels/channel_rights_actions.dart';
import '../chat/pm_screen.dart';
import '../common/command_runner.dart';
import '../common/ui.dart';
import 'moderation.dart';
import 'user_detail_screen.dart';

class UserRowActions {
  UserRowActions(
    this._context,
    this._ref,
    this.user, {
    this.includeMute = false,
  });

  final BuildContext _context;
  final WidgetRef _ref;
  final TtUser user;
  final bool includeMute;

  late final _client = _ref.read(teamTalkClientProvider);
  late final _st = _client.state;

  bool get isMe => user.id == _st.myUserId;
  Set<int> get _selection => _ref.watch(userSelectionProvider);
  bool get selectionMode => _selection.isNotEmpty;
  bool get selected => _selection.contains(user.id);
  AppLocalizations get _l10n => _context.l10n;
  String get displayName =>
      isMe ? _l10n.userYou(user.displayName) : user.displayName;
  String get menuTitle => displayName;

  String get label {
    final badges = user.statusBadges;
    return [
      displayName,
      if (badges.isNotEmpty) badges,
      if (_userIsOperator) _l10n.userOperatorTag,
      ?_transmitTag,
    ].join(', ');
  }

  TtChannel? get _channel => _st.channels[user.channelId];

  String? get _transmitTag {
    final channel = _channel;
    if (channel == null) return null;
    final talk = channel.mayTransmit(user.id, channel.voiceUsers);
    if (channel.isClassroom) {
      return talk && !channel.voiceUsers.contains(TtChannel.freeForAll)
          ? _l10n.userMayTalkTag
          : null;
    }
    return talk ? null : _l10n.userMayNotTalkTag;
  }

  VoidCallback? get onTap => selectionMode ? _toggleSelect : _openDetails;
  VoidCallback? get onLongPress => selectionMode ? _toggleSelect : null;

  void _openDetails() =>
      pushScreen(_context, UserDetailScreen(userId: user.id));

  void _sendMessage() => pushScreen(_context, PmScreen(userId: user.id));

  void _toggleSelect() {
    final was = _ref.read(userSelectionProvider).contains(user.id);
    _ref.read(userSelectionProvider.notifier).toggle(user.id);
    _ref
        .read(announcerProvider)
        .announce(
          was
              ? _l10n.userDeselected(user.displayName)
              : _l10n.userSelected(user.displayName),
        );
  }

  void _toggleMute() {
    final muted = !user.isMutedLocally;
    _client.setUserMute(user.id, muted: muted);
    _ref
        .read(announcerProvider)
        .announce(muted ? _l10n.commonMuted : _l10n.commonUnmuted);
  }

  bool get _iAmOpOfTarget =>
      user.channelId > 0 &&
      _client.isChannelOperator(_st.myUserId, user.channelId);
  bool get _canKickServer => _st.hasRight(UserRights.kickUsers);
  bool get _canBanServer => _st.hasRight(UserRights.banUsers);
  bool get _canKick => !isMe && (_canKickServer || _iAmOpOfTarget);
  bool get _canBan => !isMe && (_canBanServer || _iAmOpOfTarget);
  bool get _canOp =>
      !isMe &&
      user.channelId > 0 &&
      (_st.hasRight(UserRights.operatorEnable) || _iAmOpOfTarget);
  bool get _userIsOperator =>
      user.channelId > 0 && _client.isChannelOperator(user.id, user.channelId);
  bool get _iAmOperatorHere =>
      _st.joinedChannelId > 0 &&
      _client.isChannelOperator(_st.myUserId, _st.joinedChannelId);
  bool get _canMove => _st.hasRight(UserRights.moveUsers) || _iAmOperatorHere;

  bool get _canControlTransmit =>
      user.channelId > 0 &&
      (_iAmOpOfTarget || _st.hasRight(UserRights.modifyChannels));

  List<RowAction> get _transmitActions {
    final channel = _channel;
    if (channel == null || !_canControlTransmit) return const [];
    final talk = channel.mayTransmit(user.id, channel.voiceUsers);
    final stream = channel.mayTransmit(user.id, channel.mediaFileUsers);
    final classroom = channel.isClassroom;
    RowAction action(
      String label, {
      required bool media,
      required bool allow,
    }) => RowAction(
      label,
      () => unawaited(
        setUserTransmit(
          _context,
          _ref,
          channel,
          user.id,
          media: media,
          allow: allow,
        ),
      ),
      icon: media ? Icons.queue_music : Icons.record_voice_over,
    );
    return [
      if (classroom)
        action(
          talk ? _l10n.transmitStopAllowTalk : _l10n.transmitAllowTalk,
          media: false,
          allow: !talk,
        )
      else
        action(
          talk ? _l10n.transmitBlockTalk : _l10n.transmitUnblockTalk,
          media: false,
          allow: !talk,
        ),
      if (classroom)
        action(
          stream ? _l10n.transmitStopAllowStream : _l10n.transmitAllowStream,
          media: true,
          allow: !stream,
        )
      else
        action(
          stream ? _l10n.transmitBlockStream : _l10n.transmitUnblockStream,
          media: true,
          allow: !stream,
        ),
    ];
  }

  void _moderate(ModerationAction action) {
    final allowServer = switch (action) {
      ModerationAction.kick => _canKickServer,
      ModerationAction.ban => _canBanServer,
      ModerationAction.kickBan => _canKickServer && _canBanServer,
    };
    unawaited(
      moderateUser(_context, _ref, user, action, allowServer: allowServer),
    );
  }

  Future<void> _toggleOperator() => _ref.runCommand(
    ScaffoldMessenger.of(_context),
    () => _client.channelOperator(
      user.id,
      user.channelId,
      makeOperator: !_userIsOperator,
    ),
    announce: user.channelId == _st.joinedChannelId
        ? null
        : (l) =>
              _userIsOperator ? l.userOperatorRemoved : l.userOperatorGranted,
    errorLabel: (l) => l.actionOperator,
  );

  List<RowAction> get actions {
    if (selectionMode) {
      return [
        RowAction(
          selected ? _l10n.commonDeselect : _l10n.commonSelect,
          _toggleSelect,
        ),
      ];
    }
    return [
      RowAction(_l10n.userDetails, _openDetails, icon: Icons.person),
      RowAction(
        _l10n.userSendPrivateMessage,
        _sendMessage,
        icon: Icons.message,
      ),
      if (includeMute)
        RowAction(
          user.isMutedLocally ? _l10n.commonUnmute : _l10n.commonMute,
          _toggleMute,
          icon: user.isMutedLocally ? Icons.volume_up : Icons.volume_off,
        ),
      if (_canMove)
        RowAction(
          _l10n.commonSelect,
          _toggleSelect,
          icon: Icons.check_box_outlined,
        ),
      if (_canOp)
        RowAction(
          _userIsOperator ? _l10n.userRemoveOperator : _l10n.userMakeOperator,
          _toggleOperator,
          icon: Icons.security,
        ),
      ..._transmitActions,
      if (_canKick)
        RowAction(
          _l10n.userKick,
          () => _moderate(ModerationAction.kick),
          icon: Icons.output,
        ),
      if (_canBan)
        RowAction(
          _l10n.userBan,
          () => _moderate(ModerationAction.ban),
          icon: Icons.block,
        ),
      if (_canBan)
        RowAction(
          _l10n.userKickAndBan,
          () => _moderate(ModerationAction.kickBan),
          icon: Icons.gavel,
        ),
    ];
  }
}
