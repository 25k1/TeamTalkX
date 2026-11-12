import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/data/certificate_pin_store.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/ui/security/certificate_dialog.dart';
import 'package:teamtalkx/src/ui/security/trusted_certificates_screen.dart';

import 'support/localized_app.dart';

final _certificate = CertificateInfo(
  sha256: 'ab' * 32,
  subject: '/CN=tt.example',
  issuer: '/CN=tt.example',
  notBefore: DateTime.utc(2026),
  notAfter: DateTime.utc(2027, 3, 4),
  authorityTrusted: false,
);

UntrustedCertificate _failure(UntrustedCertificateReason reason) =>
    UntrustedCertificate(
      host: 'tt.example',
      port: 10333,
      certificate: _certificate,
      reason: reason,
    );

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues(const {'app_language': 'english'});
  return SharedPreferences.getInstance();
}

void main() {
  Future<bool? Function()> ask(
    WidgetTester tester,
    UntrustedCertificate failure,
  ) async {
    final prefs = await _prefs();
    bool? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await askToTrustCertificate(
                context,
                serverName: 'Home',
                failure: failure,
              ),
              child: const Text('connect'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('connect'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('a new certificate shows its fingerprint and can be trusted', (
    tester,
  ) async {
    final answer = await ask(tester, _failure(const NewCertificate()));
    expect(find.text('Trust this server?'), findsOneWidget);
    expect(
      find.textContaining('first encrypted connection to Home'),
      findsOneWidget,
    );
    expect(
      find.text('SHA-256 fingerprint: ${formatFingerprint('ab' * 32)}'),
      findsOneWidget,
    );
    expect(find.text('Issued to: /CN=tt.example'), findsOneWidget);
    expect(find.textContaining('Valid until: '), findsOneWidget);

    await tester.tap(find.text('Trust and connect'));
    await tester.pumpAndSettle();
    expect(answer(), isTrue);
  });

  testWidgets('a changed certificate shows the trusted one', (tester) async {
    final answer = await ask(
      tester,
      _failure(
        ChangedCertificate(
          CertificatePin(
            endpoint: 'tt.example:10333',
            sha256: 'cd' * 32,
            subject: '',
            issuer: '',
            notAfter: DateTime.utc(2027),
            savedAt: DateTime.utc(2026),
          ),
        ),
      ),
    );
    expect(find.text('Server certificate changed'), findsOneWidget);
    expect(
      find.text('Trusted fingerprint: ${formatFingerprint('cd' * 32)}'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer(), isFalse);
  });

  testWidgets('the trusted certificates screen lists and forgets', (
    tester,
  ) async {
    final prefs = await _prefs();
    final store = _MemoryPinStore([
      CertificatePin.of(
        'a.example:10333',
        _certificate,
        savedAt: DateTime.utc(2026),
      ),
      CertificatePin.authority(
        endpoint: 'b.example:10443',
        subject: '/CN=b.example',
        issuer: '/CN=Some CA',
        notAfter: DateTime.utc(2027),
        savedAt: DateTime.utc(2026),
      ),
    ]);
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          certificatePinStoreProvider.overrideWithValue(store),
        ],
        child: const LocalizedTestApp(home: TrustedCertificatesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('a.example:10333'), findsOneWidget);
    expect(find.text('b.example:10443'), findsOneWidget);
    expect(find.text('Vouched for by a certificate authority'), findsOneWidget);

    await tester.tap(find.byTooltip('Forget all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Forget all'));
    await tester.pumpAndSettle();
    expect(find.text('No trusted certificates yet'), findsOneWidget);
  });
}

class _MemoryPinStore implements CertificatePinStore {
  _MemoryPinStore(List<CertificatePin> pins) : _pins = [...pins];

  final List<CertificatePin> _pins;
  final _changes = StreamController<List<CertificatePin>>.broadcast();

  Future<void> close() => _changes.close();

  void _changed() => _changes.add(List.of(_pins));

  @override
  Future<CertificatePin?> find(String endpoint) async =>
      _pins.where((p) => p.endpoint == endpoint).firstOrNull;

  @override
  Stream<List<CertificatePin>> watchAll() async* {
    yield List.of(_pins);
    yield* _changes.stream;
  }

  @override
  Future<void> save(CertificatePin pin) async {
    _pins
      ..removeWhere((p) => p.endpoint == pin.endpoint)
      ..add(pin);
    _changed();
  }

  @override
  Future<void> forget(String endpoint) async {
    _pins.removeWhere((p) => p.endpoint == endpoint);
    _changed();
  }

  @override
  Future<void> forgetAll() async {
    _pins.clear();
    _changed();
  }
}
