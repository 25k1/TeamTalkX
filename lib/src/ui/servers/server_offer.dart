import 'package:flutter/material.dart';

import '../../domain/server_entry.dart';
import '../../l10n/l10n.dart';

enum ServerOfferChoice { connect, save }

enum ServerOfferSource { link, file }

Future<ServerOfferChoice?> confirmServerOffer(
  BuildContext context, {
  required ServerEntry entry,
  required ServerOfferSource source,
  String? connectedTo,
}) {
  final l10n = context.l10n;
  final details = <String>[
    l10n.serverOfferAddress('${entry.host}:${entry.tcpPort}'),
    if (entry.encrypted) l10n.serverOfferEncrypted,
    if (entry.username.isNotEmpty) l10n.serverOfferUsername(entry.username),
    if (entry.password.isNotEmpty) l10n.serverOfferPassword,
    if (entry.channel.isNotEmpty) l10n.serverOfferChannel(entry.channel),
    if (entry.channelPassword.isNotEmpty) l10n.serverOfferChannelPassword,
  ];
  return showDialog<ServerOfferChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(switch (source) {
        ServerOfferSource.link => l10n.serverOfferLinkTitle,
        ServerOfferSource.file => l10n.serverOfferFileTitle,
      }),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.displayName),
            for (final line in details) Text(line),
            if (connectedTo != null) ...[
              const SizedBox(height: 12),
              Text(l10n.serverOfferLeaves(connectedTo)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ServerOfferChoice.save),
          child: Text(l10n.serverAddToMine),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ServerOfferChoice.connect),
          child: Text(l10n.serverOfferConnect),
        ),
      ],
    ),
  );
}

Future<bool> confirmServerImport(
  BuildContext context,
  List<ServerEntry> entries,
) async {
  final l10n = context.l10n;
  final withPasswords = entries
      .where((e) => e.password.isNotEmpty || e.channelPassword.isNotEmpty)
      .length;
  final import = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.serverImportTitle(entries.length)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in entries)
              Text('${entry.displayName}, ${entry.host}:${entry.tcpPort}'),
            if (withPasswords > 0) ...[
              const SizedBox(height: 12),
              Text(l10n.serverImportWithPasswords(withPasswords)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.commonImport),
        ),
      ],
    ),
  );
  return import ?? false;
}

Future<bool> askExportPasswords(
  BuildContext context,
  List<ServerEntry> entries,
) async {
  if (!entries.any(
    (e) => e.password.isNotEmpty || e.channelPassword.isNotEmpty,
  )) {
    return false;
  }
  final l10n = context.l10n;
  final include = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.serverExportPasswordsTitle),
      content: Text(l10n.serverExportPasswordsBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.serverExportPasswordsInclude),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.serverExportPasswordsLeaveOut),
        ),
      ],
    ),
  );
  return include ?? false;
}

List<ServerEntry> withoutPasswords(List<ServerEntry> entries) => [
  for (final e in entries) e.copyWith(password: '', channelPassword: ''),
];
