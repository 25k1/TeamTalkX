import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

const _fingerprintA =
    '91d47022068e7f3444b137b6dc9c62ef5dc5f9ef5408f4365383ebce1a31cdc1';

class _Trust implements CertificateTrust {
  _Trust(this.answer);

  final UntrustedCertificateReason? answer;
  final seen = <(String, int, CertificateInfo)>[];

  @override
  Future<UntrustedCertificateReason?> check(
    String host,
    int port,
    CertificateInfo certificate,
  ) async {
    seen.add((host, port, certificate));
    return answer;
  }
}

void main() {
  late SecureServerSocket server;
  late List<int> received;

  setUp(() async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/tls/a.cert.pem')
      ..usePrivateKey('test/fixtures/tls/a.key.pem');
    server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    received = [];
    server.listen((socket) {
      socket.done.ignore();
      socket.listen(received.addAll, onError: (_) {}, onDone: () {});
    }, onError: (_) {});
    addTearDown(server.close);
  });

  Future<TtConnection> connect(CertificateTrust trust) async {
    final conn = TtConnection(trust: trust);
    addTearDown(conn.close);
    await conn.connect(
      InternetAddress.loopbackIPv4.address,
      server.port,
      encrypted: true,
    );
    return conn;
  }

  test(
    'an untrusted certificate fails the connect before anything is sent',
    () async {
      final trust = _Trust(const NewCertificate());
      await expectLater(
        connect(trust),
        throwsA(
          isA<UntrustedCertificate>()
              .having((f) => f.reason, 'reason', isA<NewCertificate>())
              .having((f) => f.port, 'port', server.port),
        ),
      );
      final (host, port, certificate) = trust.seen.single;
      expect(host, '127.0.0.1');
      expect(port, server.port);
      expect(certificate.sha256, _fingerprintA);
      expect(certificate.authorityTrusted, isFalse);
      expect(certificate.subject, contains('teamtalkx-test-a'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    },
  );

  test('a trusted certificate connects', () async {
    final conn = await connect(_Trust(null));
    expect(conn.isConnected, isTrue);
  });

  test('without saved pins a self-signed certificate is not trusted', () async {
    await expectLater(
      connect(const AuthorityTrustOnly()),
      throwsA(isA<UntrustedCertificate>()),
    );
  });
}
