import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/security/certificate_trust.dart';
import '../../domain/certificate.dart';
import '../../l10n/l10n.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import '../common/ui.dart';
import 'certificate_dialog.dart';

class TrustedCertificatesScreen extends ConsumerWidget {
  const TrustedCertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pins = ref.watch(certificatePinsProvider).value ?? const [];
    final store = ref.read(certificatePinStoreProvider);

    String summary(CertificatePin pin) => pin.isAuthority
        ? l10n.certificateAuthorityVouched
        : l10n.certificateFingerprint(formatFingerprint(pin.sha256!));

    Future<void> showDetails(CertificatePin pin) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pin.endpoint),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pin.isAuthority) Text(l10n.certificateAuthorityVouched),
              CertificateDetails(
                fingerprint: pin.sha256 == null
                    ? null
                    : formatFingerprint(pin.sha256!),
                subject: pin.subject,
                issuer: pin.issuer,
                notAfter: pin.notAfter,
              ),
              Text(
                l10n.certificateSaved(
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(pin.savedAt.toLocal()),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );

    Future<void> forget(CertificatePin pin) async {
      final messenger = ScaffoldMessenger.of(context);
      await store.forget(pin.endpoint);
      final text = l10n.certificateForgotten(pin.endpoint);
      messenger.showUndo(
        text,
        undoLabel: l10n.commonUndo,
        onUndo: () => unawaited(store.save(pin)),
      );
      ref.read(announcerProvider).announceShown(text);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.certificatesTitle),
        actions: [
          if (pins.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.certificatesForgetAll,
              onPressed: () async {
                if (await confirm(
                  context,
                  title: l10n.certificatesForgetAllConfirm,
                  message: l10n.certificateForgetBody,
                  confirmLabel: l10n.certificatesForgetAll,
                )) {
                  await store.forgetAll();
                }
              },
            ),
        ],
      ),
      body: pins.isEmpty
          ? Center(child: Text(l10n.certificatesNone))
          : ListView(
              children: [
                for (final pin in pins)
                  ContextMenuRow(
                    semanticsLabel: '${pin.endpoint}, ${summary(pin)}',
                    onTap: () => showDetails(pin),
                    actions: [
                      RowAction(
                        l10n.certificateDetails,
                        () => showDetails(pin),
                      ),
                      RowAction(l10n.commonForget, () => forget(pin)),
                    ],
                    child: ListTile(
                      leading: Icon(
                        pin.isAuthority ? Icons.verified : Icons.lock,
                      ),
                      title: Text(pin.endpoint),
                      subtitle: Text(summary(pin)),
                    ),
                  ),
              ],
            ),
    );
  }
}
