@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

import 'support/e2e_server.dart';

Matcher _serverError(ServerError error) =>
    isA<TtCommandError>().having((e) => e.number, 'number', error.code);

void main() {
  group('connection', skip: e2eSkip, () {
    test('logs in over TCP and receives the server state', () async {
      final client = await loginAs(E2eAccount.admin);

      expect(client.state.myUserId, greaterThan(0));
      expect(client.myUserType, 2);
      expect(client.state.serverInfo.name, 'TeamTalkX E2E');
      expect(client.state.serverInfo.motd, contains('Welcome'));
      expect(client.state.rootChannel?.id, E2eChannel.root);
      expect({
        for (final c in client.state.channels.values) c.id: c.name,
      }, containsPair(E2eChannel.speex, 'Speex'));
      expect(client.udpPort, e2ePort);
    });

    for (final transport in [E2eTransport.tls, E2eTransport.pro]) {
      test(
        'logs in over ${transport.name} TLS',
        skip: transport.skip,
        () async {
          final client = await loginAs(E2eAccount.admin, transport: transport);

          expect(client.isConnected, isTrue);
          expect(client.state.myUserId, greaterThan(0));
          expect(client.state.serverInfo.name, 'TeamTalkX E2E');
          expect(client.udpPort, transport.udpPort);
        },
      );
    }

    test(
      'asks about a new certificate, then trusts only it (D5, D143)',
      skip: E2eTransport.tls.skip,
      () async {
        final trust = e2eTrust();
        Future<ProtocolClient> connect() async {
          final client = ProtocolClient(trust: trust);
          addTearDown(client.dispose);
          await client.connect(
            host: e2eHost,
            tcpPort: e2eTlsPort,
            encrypted: true,
          );
          return client;
        }

        final UntrustedCertificate first;
        try {
          await connect();
          fail('connected to an untrusted server');
        } on UntrustedCertificate catch (e) {
          first = e;
        }
        expect(first.reason, isA<NewCertificate>());
        expect(first.certificate.sha256, hasLength(64));
        expect(first.certificate.authorityTrusted, isFalse);

        await trust.accept(e2eHost, e2eTlsPort, first.certificate);
        final client = await connect();
        await client.login(
          nickname: 'tofu-e2e',
          username: E2eAccount.alice.username,
          password: E2eAccount.alice.password,
        );
        expect(client.state.myUserId, greaterThan(0));

        await trust.accept(
          e2eHost,
          e2eTlsPort,
          CertificateInfo(
            sha256: '00' * 32,
            subject: '',
            issuer: '',
            notBefore: DateTime.utc(2026),
            notAfter: DateTime.utc(2027),
            authorityTrusted: false,
          ),
        );
        await expectLater(
          connect(),
          throwsA(
            isA<UntrustedCertificate>().having(
              (e) => e.reason,
              'reason',
              isA<ChangedCertificate>(),
            ),
          ),
        );
      },
    );

    test('only users who may update the server learn its UDP port', () async {
      final alice = await loginAs(E2eAccount.alice);
      expect(alice.serverProperties, isNotNull);
      expect(alice.udpPort, 0);
    });

    test('rejects a wrong password as an invalid account', () async {
      final client = ProtocolClient();
      addTearDown(client.dispose);
      await client.connect(host: e2eHost, tcpPort: e2ePort);

      await expectLater(
        client.login(
          nickname: 'intruder',
          username: E2eAccount.alice.username,
          password: 'wrong',
        ),
        throwsA(_serverError(ServerError.invalidAccount)),
      );
    });

    test('others see a user log in and out', () async {
      final bob = await loginAs(E2eAccount.bob);
      final nickname = uniqueName('alice');
      final loggedIn = nextEvent<UserLoggedInEvent>(
        bob,
        (e) => e.user.nickname == nickname,
      );
      final alice = await loginAs(E2eAccount.alice, nickname: nickname);
      final aliceId = (await loggedIn).user.id;
      expect(aliceId, alice.state.myUserId);

      final loggedOut = nextEvent<UserLoggedOutEvent>(
        bob,
        (e) => e.user.id == aliceId,
      );
      await alice.disconnect();
      await loggedOut;
      expect(bob.state.users.containsKey(aliceId), isFalse);
    });
  });
}
