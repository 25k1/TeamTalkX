import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/data/certificate_pin_store.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

const e2eHost = String.fromEnvironment('TT_E2E_HOST');
const e2ePort = int.fromEnvironment('TT_E2E_PORT', defaultValue: 10333);
const e2eTlsPort = int.fromEnvironment('TT_E2E_TLS_PORT', defaultValue: 10443);

const e2eProPort = int.fromEnvironment('TT_E2E_PRO_PORT');

const String? e2eSkip = e2eHost == ''
    ? 'Needs the E2E server: --dart-define=TT_E2E_HOST=<host>'
    : null;

enum E2eTransport {
  tcp(e2ePort, encrypted: false, udpPort: e2ePort),

  tls(e2eTlsPort, encrypted: true, udpPort: e2ePort),

  pro(e2eProPort, encrypted: true, udpPort: e2eProPort);

  const E2eTransport(
    this.port, {
    required this.encrypted,
    required this.udpPort,
  });

  final int port;
  final bool encrypted;

  final int udpPort;

  String? get skip =>
      e2eSkip ??
      (port == 0
          ? 'Needs the Pro server: --dart-define=TT_E2E_PRO_PORT=<port>'
          : null);
}

enum E2eAccount {
  admin('admin', 'admin-e2e'),
  alice('alice', 'alice-e2e'),
  bob('bob', 'bob-e2e'),
  restricted('restricted', 'restricted-e2e');

  const E2eAccount(this.username, this.password);

  final String username;
  final String password;
}

abstract final class E2eChannel {
  static const root = 1;
  static const opusStereo = 2;
  static const speex = 3;
  static const speexVbr = 4;
  static const locked = 5;
  static const lockedPassword = 'locked-e2e';
  static const files = 6;
}

const e2eTimeout = Duration(seconds: 10);

final _random = Random();

String uniqueName(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';

PinnedCertificateTrust e2eTrust() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return PinnedCertificateTrust(CertificatePinStore(db));
}

class TrustOnFirstUse implements CertificateTrust {
  TrustOnFirstUse(this._trust);

  final PinnedCertificateTrust _trust;

  @override
  Future<UntrustedCertificateReason?> check(
    String host,
    int port,
    CertificateInfo certificate,
  ) async {
    final reason = await _trust.check(host, port, certificate);
    if (reason is! NewCertificate) return reason;
    await _trust.accept(host, port, certificate);
    return null;
  }
}

Future<ProtocolClient> loginAs(
  E2eAccount account, {
  E2eTransport transport = E2eTransport.tcp,
  String? nickname,
}) async {
  final client = ProtocolClient(trust: TrustOnFirstUse(e2eTrust()));
  addTearDown(client.dispose);
  await client.connectAndLogin(
    host: e2eHost,
    tcpPort: transport.port,
    encrypted: transport.encrypted,
    nickname: nickname ?? '${account.username}-e2e',
    username: account.username,
    password: account.password,
  );
  return client;
}

Future<T> nextEvent<T extends TtEvent>(
  ProtocolClient client, [
  bool Function(T event)? where,
]) => client.events
    .where((e) => e is T && (where == null || where(e)))
    .cast<T>()
    .first
    .timeout(e2eTimeout);
