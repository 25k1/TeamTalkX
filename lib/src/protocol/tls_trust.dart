import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import '../domain/certificate.dart';
import '../domain/failure.dart';

class TlsTrustCheck {
  TlsTrustCheck(this.trust);

  final CertificateTrust trust;
  bool _authorityTrusted = true;

  bool onBadCertificate(X509Certificate _) {
    _authorityTrusted = false;
    return true;
  }

  Future<void> verify(SecureSocket socket, String host, int port) async {
    final peer = socket.peerCertificate;
    if (peer == null) {
      socket.destroy();
      throw const SecureConnectionFailed();
    }
    final certificate = certificateInfo(
      peer,
      authorityTrusted: _authorityTrusted,
    );
    final reason = await trust.check(host, port, certificate);
    if (reason == null) return;
    socket.destroy();
    throw UntrustedCertificate(
      host: host,
      port: port,
      certificate: certificate,
      reason: reason,
    );
  }
}

CertificateInfo certificateInfo(
  X509Certificate certificate, {
  required bool authorityTrusted,
}) => CertificateInfo(
  sha256: sha256Hex(certificate.der),
  subject: certificate.subject,
  issuer: certificate.issuer,
  notBefore: certificate.startValidity,
  notAfter: certificate.endValidity,
  authorityTrusted: authorityTrusted,
);

String sha256Hex(Uint8List bytes) {
  final digest = SHA256Digest().process(bytes);
  return [for (final b in digest) b.toRadixString(16).padLeft(2, '0')].join();
}
