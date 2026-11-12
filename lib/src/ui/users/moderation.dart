import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../common/command_runner.dart';

enum ModerationAction {
  kick,
  ban,
  kickBan;

  String label(AppLocalizations l10n) => switch (this) {
    kick => l10n.userKick,
    ban => l10n.userBan,
    kickBan => l10n.userKickAndBan,
  };
}

enum _Scope { channel, server }

enum _BanBy {
  ipAddress(BanTypes.ipAddress),
  username(BanTypes.username),
  both(BanTypes.ipAddress | BanTypes.username);

  const _BanBy(this.types);
  final int types;

  String label(AppLocalizations l10n) => switch (this) {
    ipAddress => l10n.banByIp,
    username => l10n.banByUsername,
    both => l10n.banByBoth,
  };
}

Future<void> moderateUser(
  BuildContext context,
  WidgetRef ref,
  TtUser user,
  ModerationAction action, {
  bool allowServer = true,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showDialog<(_Scope, _BanBy)>(
    context: context,
    builder: (_) => _ModerationDialog(
      userName: user.displayName,
      action: action,
      allowServer: allowServer,
      hasUsername: user.username.isNotEmpty,
    ),
  );
  if (choice == null) return;
  final (scope, banBy) = choice;

  final client = ref.read(teamTalkClientProvider);
  final channelId = scope == _Scope.server ? 0 : user.channelId;
  await ref.runCommand(
    messenger,
    () async {
      switch (action) {
        case ModerationAction.kick:
          await client.kickUser(user.id, channelId: channelId);
        case ModerationAction.ban:
          await client.banUser(
            user.id,
            channelId: channelId,
            banTypes: banBy.types,
          );
        case ModerationAction.kickBan:
          await client.banUser(
            user.id,
            channelId: channelId,
            banTypes: banBy.types,
          );
          await client.kickUser(user.id, channelId: channelId);
      }
    },
    announce: (l) => scope == _Scope.server
        ? l.moderationDoneServer(action.label(l), user.displayName)
        : l.moderationDoneChannel(action.label(l), user.displayName),
    errorLabel: (l) => l.actionModerate(action.label(l)),
  );
}

class _ModerationDialog extends StatefulWidget {
  const _ModerationDialog({
    required this.userName,
    required this.action,
    required this.allowServer,
    required this.hasUsername,
  });

  final String userName;
  final ModerationAction action;
  final bool allowServer;
  final bool hasUsername;

  @override
  State<_ModerationDialog> createState() => _ModerationDialogState();
}

class _ModerationDialogState extends State<_ModerationDialog> {
  _Scope _scope = _Scope.channel;
  _BanBy _banBy = _BanBy.ipAddress;

  bool get _bans => widget.action != ModerationAction.kick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(
        l10n.moderationConfirm(widget.action.label(l10n), widget.userName),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.allowServer)
              RadioGroup<_Scope>(
                groupValue: _scope,
                onChanged: (value) {
                  if (value != null) setState(() => _scope = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<_Scope>(
                      title: Text(l10n.moderationFromChannel),
                      value: _Scope.channel,
                    ),
                    RadioListTile<_Scope>(
                      title: Text(l10n.moderationFromServer),
                      value: _Scope.server,
                    ),
                  ],
                ),
              )
            else
              Text(l10n.moderationFromThisChannel),
            if (_bans && widget.hasUsername) ...[
              const Divider(),
              Text(l10n.banBy),
              RadioGroup<_BanBy>(
                groupValue: _banBy,
                onChanged: (value) {
                  if (value != null) setState(() => _banBy = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final by in _BanBy.values)
                      RadioListTile<_BanBy>(
                        title: Text(by.label(l10n)),
                        value: by,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((widget.allowServer ? _scope : _Scope.channel, _banBy)),
          child: Text(widget.action.label(l10n)),
        ),
      ],
    );
  }
}
