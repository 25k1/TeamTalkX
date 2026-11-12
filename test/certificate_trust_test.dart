import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/data/certificate_pin_store.dart';
import 'package:teamtalkx/src/domain/certificate.dart';

CertificateInfo cert(String sha, {bool authority = false}) => CertificateInfo(
  sha256: sha,
  subject: '/CN=tt.example',
  issuer: authority ? '/CN=Some CA' : '/CN=tt.example',
  notBefore: DateTime.utc(2026),
  notAfter: DateTime.utc(2027),
  authorityTrusted: authority,
);

void main() {
  late AppDatabase db;
  late CertificatePinStore store;
  late PinnedCertificateTrust trust;
  final now = DateTime.utc(2026, 11, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = CertificatePinStore(db);
    trust = PinnedCertificateTrust(store, now: () => now);
  });
  tearDown(() => db.close());

  test('a new self-signed certificate is asked about (D143)', () async {
    expect(
      await trust.check('tt.example', 10333, cert('aa')),
      isA<NewCertificate>(),
    );
    expect(await store.find('tt.example:10333'), isNull, reason: 'not saved');
  });

  test('an accepted certificate is trusted, another one is a change', () async {
    await trust.accept('TT.example', 10333, cert('aa'));
    expect(await trust.check('tt.example', 10333, cert('aa')), isNull);

    final changed = await trust.check('tt.example', 10333, cert('bb'));
    expect(changed, isA<ChangedCertificate>());
    expect((changed! as ChangedCertificate).previous.sha256, 'aa');
    expect(
      await trust.check('tt.example', 10334, cert('aa')),
      isA<NewCertificate>(),
      reason: 'pins are per port',
    );
  });

  test(
    'authority-vouched certificates are trusted and remembered (D142)',
    () async {
      expect(
        await trust.check('tt.example', 10443, cert('aa', authority: true)),
        isNull,
      );
      expect(
        await trust.check('tt.example', 10443, cert('cc', authority: true)),
        isNull,
        reason: 'a renewal',
      );
      final pin = await store.find('tt.example:10443');
      expect(pin!.isAuthority, isTrue);
      expect(pin.savedAt.isAtSameMomentAs(now), isTrue);

      final downgraded = await trust.check('tt.example', 10443, cert('dd'));
      expect(downgraded, isA<ChangedCertificate>());
      expect((downgraded! as ChangedCertificate).previous.isAuthority, isTrue);
    },
  );

  test('a pinned server that gets an authority-vouched certificate', () async {
    await trust.accept('tt.example', 10333, cert('aa'));
    expect(
      await trust.check('tt.example', 10333, cert('bb', authority: true)),
      isNull,
    );
    expect((await store.find('tt.example:10333'))!.isAuthority, isTrue);
  });

  test('forgetting', () async {
    await trust.accept('a', 1, cert('aa'));
    await trust.accept('b', 2, cert('bb'));
    expect((await store.watchAll().first).map((p) => p.endpoint), [
      'a:1',
      'b:2',
    ]);
    await store.forget('a:1');
    expect(await trust.check('a', 1, cert('aa')), isA<NewCertificate>());
    await store.forgetAll();
    expect(await store.watchAll().first, isEmpty);
  });

  test('fingerprints read in groups of four', () {
    expect(formatFingerprint('0a1b2c3d4e5f'), '0A1B 2C3D 4E5F');
  });
}
