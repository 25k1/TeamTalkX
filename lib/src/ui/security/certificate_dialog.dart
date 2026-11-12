import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/certificate.dart';
import '../../domain/failure.dart';
import '../../l10n/l10n.dart';

Future<bool> askToTrustCertificate(
  BuildContext context, {
  required String serverName,
  required UntrustedCertificate failure,
}) async {
  final trusted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _CertificateDialog(serverName: serverName, failure: failure),
  );
  return trusted ?? false;
}

class _CertificateDialog extends StatelessWidget {
  const _CertificateDialog({required this.serverName, required this.failure});

  final String serverName;
  final UntrustedCertificate failure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final certificate = failure.certificate;
    final changed = switch (failure.reason) {
      ChangedCertificate(:final previous) => previous,
      NewCertificate() => null,
    };
    final fingerprint = formatFingerprint(certificate.sha256);
    return AlertDialog(
      title: Text(
        changed == null
            ? l10n.certificateNewTitle
            : l10n.certificateChangedTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              changed == null
                  ? l10n.certificateNewBody(serverName)
                  : l10n.certificateChangedBody(serverName),
            ),
            if (changed != null && changed.isAuthority) ...[
              const SizedBox(height: 8),
              Text(l10n.certificateWasAuthority),
            ],
            const SizedBox(height: 12),
            CertificateDetails(
              fingerprint: fingerprint,
              subject: certificate.subject,
              issuer: certificate.issuer,
              notAfter: certificate.notAfter,
            ),
            if (changed?.sha256 case final previous?) ...[
              const SizedBox(height: 8),
              Text(
                l10n.certificatePreviousFingerprint(
                  formatFingerprint(previous),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: fingerprint)));
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(l10n.certificateCopied)));
          },
          child: Text(l10n.certificateCopyFingerprint),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.certificateTrust),
        ),
      ],
    );
  }
}

class CertificateDetails extends StatelessWidget {
  const CertificateDetails({
    super.key,
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    required this.notAfter,
  });

  final String? fingerprint;
  final String subject;
  final String issuer;
  final DateTime notAfter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(notAfter.toLocal());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fingerprint case final fingerprint?)
          Text(l10n.certificateFingerprint(fingerprint)),
        Text(l10n.certificateSubject(subject)),
        Text(l10n.certificateIssuer(issuer)),
        Text(l10n.certificateValidUntil(date)),
      ],
    );
  }
}
