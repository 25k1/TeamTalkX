import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../a11y/dialogs.dart';
import '../common/command_runner.dart';

Future<void> becomeOperator(
  BuildContext context,
  WidgetRef ref,
  TtChannel channel,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final password = await promptText(
    context,
    title: l10n.operatorBecomeTitle(channel.isRoot ? '/' : channel.name),
    label: l10n.operatorPassword,
    obscureText: true,
    submitLabel: l10n.operatorBecome,
  );
  if (password == null) return;
  final client = ref.read(teamTalkClientProvider);
  await ref.runCommand(
    messenger,
    () => client.channelOperator(
      client.state.myUserId,
      channel.id,
      makeOperator: true,
      password: password,
    ),
    errorLabel: (l) => l.actionOperator,
  );
}

Future<void> stopBeingOperator(
  BuildContext context,
  WidgetRef ref,
  TtChannel channel,
) {
  final client = ref.read(teamTalkClientProvider);
  return ref.runCommand(
    ScaffoldMessenger.of(context),
    () => client.channelOperator(
      client.state.myUserId,
      channel.id,
      makeOperator: false,
    ),
    errorLabel: (l) => l.actionOperator,
  );
}

Future<void> setUserTransmit(
  BuildContext context,
  WidgetRef ref,
  TtChannel channel,
  int userId, {
  required bool media,
  required bool allow,
}) {
  final listed = channel.isClassroom == allow;
  Set<int> change(Set<int> users) =>
      listed ? {...users, userId} : ({...users}..remove(userId));
  return _saveTransmit(
    context,
    ref,
    channel,
    voice: media ? channel.voiceUsers : change(channel.voiceUsers),
    mediaFiles: media ? change(channel.mediaFileUsers) : channel.mediaFileUsers,
  );
}

Future<void> setEveryoneMayTalk(
  BuildContext context,
  WidgetRef ref,
  TtChannel channel, {
  required bool everyone,
}) => _saveTransmit(
  context,
  ref,
  channel,
  voice: everyone
      ? {...channel.voiceUsers, TtChannel.freeForAll}
      : ({...channel.voiceUsers}..remove(TtChannel.freeForAll)),
  mediaFiles: channel.mediaFileUsers,
);

Future<void> _saveTransmit(
  BuildContext context,
  WidgetRef ref,
  TtChannel channel, {
  required Set<int> voice,
  required Set<int> mediaFiles,
}) => ref.runCommand(
  ScaffoldMessenger.of(context),
  () => ref
      .read(teamTalkClientProvider)
      .setTransmitUsers(channel.id, voice: voice, mediaFiles: mediaFiles),
  errorLabel: (l) => l.actionTransmitControl,
);
