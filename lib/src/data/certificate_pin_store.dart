import 'package:drift/drift.dart';

import '../domain/certificate.dart';
import 'app_database.dart';

class CertificatePinStore {
  CertificatePinStore(this._db);

  final AppDatabase _db;

  Future<CertificatePin?> find(String endpoint) async {
    final row = await (_db.select(
      _db.certificatePins,
    )..where((t) => t.endpoint.equals(endpoint))).getSingleOrNull();
    return row == null ? null : _pin(row);
  }

  Stream<List<CertificatePin>> watchAll() =>
      (_db.select(_db.certificatePins)
            ..orderBy([(t) => OrderingTerm.asc(t.endpoint)]))
          .watch()
          .map((rows) => [for (final row in rows) _pin(row)]);

  Future<void> save(CertificatePin pin) => _db
      .into(_db.certificatePins)
      .insertOnConflictUpdate(
        CertificatePinsCompanion.insert(
          endpoint: pin.endpoint,
          sha256: Value(pin.sha256),
          subject: pin.subject,
          issuer: pin.issuer,
          notAfter: pin.notAfter,
          savedAt: pin.savedAt,
        ),
      );

  Future<void> forget(String endpoint) => (_db.delete(
    _db.certificatePins,
  )..where((t) => t.endpoint.equals(endpoint))).go();

  Future<void> forgetAll() => _db.delete(_db.certificatePins).go();

  CertificatePin _pin(CertificatePinRow row) => CertificatePin(
    endpoint: row.endpoint,
    sha256: row.sha256,
    subject: row.subject,
    issuer: row.issuer,
    notAfter: row.notAfter,
    savedAt: row.savedAt,
  );
}
