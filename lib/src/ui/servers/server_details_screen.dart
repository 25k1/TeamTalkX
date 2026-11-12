import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/servers/server_list_providers.dart';
import '../../domain/server_entry.dart';
import '../../l10n/l10n.dart';
import 'server_list_screen.dart';

class ServerDetailsScreen extends ConsumerWidget {
  const ServerDetailsScreen({
    super.key,
    required this.entry,
    required this.index,
    required this.onConnect,
    this.onEdit,
    required this.onFavorite,
  });

  final ServerEntry entry;
  final int? index;
  final VoidCallback onConnect;
  final VoidCallback? onEdit;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final index = this.index;
    final mine = ref.watch(serverListProvider).value;
    final server = index != null && mine != null && index < mine.length
        ? mine[index]
        : entry;
    Widget row(String title, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : ListTile(title: Text(title), subtitle: Text(value));
    return Scaffold(
      appBar: AppBar(title: Text(server.displayName)),
      body: ListView(
        children: [
          row(l10n.serverDetailsKind, server.listingType.marker(l10n)),
          row(l10n.serverDetailsAddress, '${server.host}:${server.tcpPort}'),
          if (server.encrypted) row(l10n.serverOfferEncrypted, l10n.commonYes),
          if (server.username.isNotEmpty)
            row(l10n.commonUsername, server.username),
          if (server.userCount > 0)
            row(
              l10n.serverDetailsUsers,
              l10n.serverUserCount(server.userCount),
            ),
          row(l10n.serverDetailsCountry, server.country),
          row(l10n.serverDetailsMotd, server.motd),
          if (server.lastConnected case final last?)
            row(
              l10n.serverDetailsLastConnected,
              lastConnectedText(context, last),
            ),
          if (server.favorite) row(l10n.serverFavorite, l10n.commonYes),
          if (server.connectOnStartup)
            row(l10n.serverConnectOnStartup, l10n.commonYes),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: Text(l10n.serverOfferConnect),
                  onPressed: onConnect,
                ),
                if (onEdit case final edit?)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: Text(l10n.commonEdit),
                    onPressed: edit,
                  ),
                OutlinedButton.icon(
                  icon: Icon(server.favorite ? Icons.star : Icons.star_border),
                  label: Text(
                    server.favorite
                        ? l10n.serverUnfavorite
                        : l10n.serverMakeFavorite,
                  ),
                  onPressed: onFavorite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
