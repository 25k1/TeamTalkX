library;

class CertificateInfo {
  const CertificateInfo({
    required this.sha256,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
    required this.authorityTrusted,
  });

  final String sha256;
  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;

  final bool authorityTrusted;
}

class CertificatePin {
  const CertificatePin({
    required this.endpoint,
    required this.sha256,
    required this.subject,
    required this.issuer,
    required this.notAfter,
    required this.savedAt,
  });

  const CertificatePin.authority({
    required this.endpoint,
    required this.subject,
    required this.issuer,
    required this.notAfter,
    required this.savedAt,
  }) : sha256 = null;

  CertificatePin.of(
    this.endpoint,
    CertificateInfo certificate, {
    required this.savedAt,
  }) : sha256 = certificate.authorityTrusted ? null : certificate.sha256,
       subject = certificate.subject,
       issuer = certificate.issuer,
       notAfter = certificate.notAfter;

  final String endpoint;

  final String? sha256;
  final String subject;
  final String issuer;
  final DateTime notAfter;
  final DateTime savedAt;

  bool get isAuthority => sha256 == null;
}

String certificateEndpoint(String host, int port) =>
    '${host.toLowerCase()}:$port';

String formatFingerprint(String sha256) {
  final hex = sha256.toUpperCase();
  return [
    for (var i = 0; i < hex.length; i += 4)
      hex.substring(i, i + 4 > hex.length ? hex.length : i + 4),
  ].join(' ');
}

abstract interface class CertificateTrust {
  Future<UntrustedCertificateReason?> check(
    String host,
    int port,
    CertificateInfo certificate,
  );
}

sealed class UntrustedCertificateReason {
  const UntrustedCertificateReason();
}

final class NewCertificate extends UntrustedCertificateReason {
  const NewCertificate();
}

final class ChangedCertificate extends UntrustedCertificateReason {
  const ChangedCertificate(this.previous);
  final CertificatePin previous;
}

class AuthorityTrustOnly implements CertificateTrust {
  const AuthorityTrustOnly();

  @override
  Future<UntrustedCertificateReason?> check(
    String host,
    int port,
    CertificateInfo certificate,
  ) async => certificate.authorityTrusted ? null : const NewCertificate();
}
