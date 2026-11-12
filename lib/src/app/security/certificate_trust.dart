import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../data/certificate_pin_store.dart';
import '../../diagnostics/log.dart';
import '../../domain/certificate.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final certificatePinStoreProvider = Provider<CertificatePinStore>(
  (ref) => CertificatePinStore(ref.watch(appDatabaseProvider)),
);

final certificateTrustProvider = Provider<PinnedCertificateTrust>(
  (ref) =>
      PinnedCertificateTrust.lazy(() => ref.read(certificatePinStoreProvider)),
);

final certificatePinsProvider = StreamProvider<List<CertificatePin>>(
  (ref) => ref.watch(certificatePinStoreProvider).watchAll(),
);

class PinnedCertificateTrust implements CertificateTrust {
  PinnedCertificateTrust(CertificatePinStore store, {DateTime Function()? now})
    : this.lazy(() => store, now: now);

  PinnedCertificateTrust.lazy(this._openStore, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final CertificatePinStore Function() _openStore;
  CertificatePinStore get _store => _openStore();
  final DateTime Function() _now;

  @override
  Future<UntrustedCertificateReason?> check(
    String host,
    int port,
    CertificateInfo certificate,
  ) async {
    final endpoint = certificateEndpoint(host, port);
    final pin = await _store.find(endpoint);
    if (certificate.authorityTrusted) {
      if (pin == null || !pin.isAuthority) {
        appLog.i(
          'tls',
          '$endpoint: a certificate authority vouches for the certificate',
        );
        await _store.save(
          CertificatePin.of(endpoint, certificate, savedAt: _now()),
        );
      }
      return null;
    }
    if (pin == null) return const NewCertificate();
    if (!pin.isAuthority && pin.sha256 == certificate.sha256) return null;
    appLog.w('tls', "$endpoint: the certificate isn't the trusted one");
    return ChangedCertificate(pin);
  }

  Future<void> accept(String host, int port, CertificateInfo certificate) {
    final endpoint = certificateEndpoint(host, port);
    appLog.i(
      'tls',
      '$endpoint: the user trusted certificate ${certificate.sha256}',
    );
    return _store.save(
      CertificatePin.of(endpoint, certificate, savedAt: _now()),
    );
  }
}
