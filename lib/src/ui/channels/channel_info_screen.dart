import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';

Map<int, String> _channelTypeLabels(AppLocalizations l10n) => {
  ChannelTypes.permanent: l10n.channelTypePermanent,
  ChannelTypes.soloTransmit: l10n.channelTypeSoloTransmit,
  ChannelTypes.classroom: l10n.channelTypeClassroom,
  ChannelTypes.operatorRecvOnly: l10n.channelTypeOperatorRecvOnly,
  ChannelTypes.noVoiceActivation: l10n.channelTypeNoVoiceActivation,
  ChannelTypes.noRecording: l10n.channelTypeNoRecording,
  ChannelTypes.hidden: l10n.channelTypeHidden,
};

class ChannelInfoScreen extends ConsumerWidget {
  const ChannelInfoScreen({super.key, required this.channelId});

  final int channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serverStateTickProvider);
    final client = ref.watch(teamTalkClientProvider);
    final state = client.state;
    final channel = state.channels[channelId];
    final l10n = context.l10n;

    if (channel == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.channelInformation)),
        body: Center(child: Text(l10n.channelNoLongerAvailable)),
      );
    }

    final path = client.channelPath(channel.id);
    final name = channel.isRoot
        ? (state.serverInfo.name.isEmpty
              ? (path.isEmpty ? '/' : path)
              : state.serverInfo.name)
        : (path.isEmpty ? channel.name : path);
    final userCount = state.users.values
        .where((u) => u.channelId == channel.id)
        .length;
    final flags = [
      for (final entry in _channelTypeLabels(l10n).entries)
        if (channel.channelType & entry.key != 0) entry.value,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.channelInformation)),
      body: ListView(
        children: [
          _row(l10n.commonName, name),
          if (channel.topic.isNotEmpty)
            _row(l10n.channelInfoTopic, channel.topic),
          _row(
            l10n.channelInfoUsers,
            channel.maxUsers > 0
                ? l10n.channelInfoUsersOf(userCount, channel.maxUsers)
                : '$userCount',
          ),
          _row(
            l10n.channelInfoPasswordProtected,
            channel.hasPassword ? l10n.commonYes : l10n.commonNo,
          ),
          _row(
            l10n.channelInfoType,
            flags.isEmpty ? l10n.channelTypeDefault : flags.join(', '),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) =>
      ListTile(title: Text(label), subtitle: Text(value));
}
