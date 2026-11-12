@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

import 'support/e2e_server.dart';

Future<List<TtUserAccount>> _listAccounts(ProtocolClient admin) async {
  final accounts = <TtUserAccount>[];
  final sub = admin.events.listen((e) {
    if (e is UserAccountEvent) accounts.add(e.account);
  });
  await admin.listUserAccounts();
  await sub.cancel();
  return accounts;
}

void main() {
  group('user accounts', skip: e2eSkip, () {
    test('an account can be created, used and deleted', () async {
      final admin = await loginAs(E2eAccount.admin);
      final username = uniqueName('user');
      const rights = UserRights.viewAllUsers | UserRights.textMessageChannel;

      await admin.createUserAccount(
        TtUserAccount(
          username: username,
          password: 'pw-e2e',
          userRights: rights,
          note: 'Created by E2E',
        ),
      );
      addTearDown(() async {
        if (!admin.isConnected) return;
        try {
          await admin.deleteUserAccount(username);
        } on TtCommandError catch (_) {}
      });

      final listed = (await _listAccounts(
        admin,
      )).where((a) => a.username == username).single;
      expect(listed.userRights, rights);
      expect(listed.note, 'Created by E2E');

      final user = ProtocolClient();
      addTearDown(user.dispose);
      await user.connectAndLogin(
        host: e2eHost,
        tcpPort: e2ePort,
        nickname: 'new user',
        username: username,
        password: 'pw-e2e',
      );
      expect(user.state.myUserRights, rights);
      await user.disconnect();

      await admin.deleteUserAccount(username);
      expect(
        (await _listAccounts(admin)).map((a) => a.username),
        isNot(contains(username)),
      );

      final again = ProtocolClient();
      addTearDown(again.dispose);
      await again.connect(host: e2eHost, tcpPort: e2ePort);
      await expectLater(
        again.login(nickname: 'gone', username: username, password: 'pw-e2e'),
        throwsA(
          isA<TtCommandError>().having(
            (e) => e.number,
            'number',
            ServerError.invalidAccount.code,
          ),
        ),
      );
    });
  });
}
