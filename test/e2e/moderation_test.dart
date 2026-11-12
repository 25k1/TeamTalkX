@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

import 'support/e2e_server.dart';

Matcher _serverError(ServerError error) =>
    isA<TtCommandError>().having((e) => e.number, 'number', error.code);

void main() {
  group('moderation', skip: e2eSkip, () {
    test('a channel kick names the channel and keeps the connection', () async {
      final admin = await loginAs(E2eAccount.admin);
      final alice = await loginAs(E2eAccount.alice);
      await alice.joinChannel(E2eChannel.root);

      final kicked = nextEvent<MyselfKickedEvent>(alice);
      await admin.kickUser(alice.state.myUserId, channelId: E2eChannel.root);
      final event = await kicked;

      expect(event.fromServer, isFalse);
      expect(event.channelId, E2eChannel.root);
      expect(event.kicker?.id, admin.state.myUserId);
      expect(alice.isConnected, isTrue);
    });

    test('a server kick has no channel and logs the user out', () async {
      final admin = await loginAs(E2eAccount.admin);
      final alice = await loginAs(E2eAccount.alice);

      final kicked = nextEvent<MyselfKickedEvent>(alice);
      final loggedOut = nextEvent<MyselfLoggedOutEvent>(alice);
      await admin.kickUser(alice.state.myUserId);
      final event = await kicked;

      expect(event.fromServer, isTrue);
      expect(event.kicker?.id, admin.state.myUserId);
      await loggedOut;
      expect(alice.state.myUserId, 0);
    });

    test('the operator password makes an operator who can block talk '
        '(D95, D96, D156)', () async {
      final alice = await loginAs(E2eAccount.alice);
      final bob = await loginAs(E2eAccount.bob);
      await alice.joinChannel(
        E2eChannel.locked,
        password: E2eChannel.lockedPassword,
      );
      await bob.joinChannel(
        E2eChannel.locked,
        password: E2eChannel.lockedPassword,
      );
      final aliceId = alice.state.myUserId;
      final bobId = bob.state.myUserId;

      await expectLater(
        alice.channelOperator(
          aliceId,
          E2eChannel.locked,
          makeOperator: true,
          password: 'wrong',
        ),
        throwsA(_serverError(ServerError.incorrectOpPassword)),
      );

      final opped = nextEvent<ChannelUpdateEvent>(
        bob,
        (e) =>
            e.channel.id == E2eChannel.locked &&
            e.channel.operators.contains(aliceId),
      );
      await alice.channelOperator(
        aliceId,
        E2eChannel.locked,
        makeOperator: true,
        password: 'op-e2e',
      );
      await opped;

      final blocked = nextEvent<ChannelUpdateEvent>(
        bob,
        (e) => e.channel.voiceUsers.contains(bobId),
      );
      await alice.setTransmitUsers(
        E2eChannel.locked,
        voice: {bobId},
        mediaFiles: const {},
      );
      final channel = (await blocked).channel;
      expect(channel.mayTransmit(bobId, channel.voiceUsers), isFalse);
      expect(channel.mayTransmit(aliceId, channel.voiceUsers), isTrue);

      await alice.setTransmitUsers(
        E2eChannel.locked,
        voice: const {},
        mediaFiles: const {},
      );
    });

    test('a ban by username from a channel is listed as such (D93)', () async {
      final admin = await loginAs(E2eAccount.admin);
      final bob = await loginAs(E2eAccount.bob);
      await bob.joinChannel(E2eChannel.files);

      await admin.banUser(
        bob.state.myUserId,
        channelId: E2eChannel.files,
        banTypes: BanTypes.username,
      );
      final listed = nextEvent<BannedUserEvent>(
        admin,
        (e) => e.ban.username == E2eAccount.bob.username,
      );
      await admin.listBans(channelId: E2eChannel.files);
      final ban = (await listed).ban;
      expect(ban.banTypes, BanTypes.username | BanTypes.channel);
      expect(ban.channelPath, isNotEmpty);

      await admin.unbanUser(ban);
    });

    test(
      'admins get the server statistics, others are refused (D158)',
      () async {
        final admin = await loginAs(E2eAccount.admin);
        final stats = await admin.queryServerStats();
        expect(stats.usersServed, greaterThan(0));
        expect(stats.uptime, greaterThan(Duration.zero));

        final alice = await loginAs(E2eAccount.alice);
        await expectLater(
          alice.queryServerStats(),
          throwsA(_serverError(ServerError.notAuthorized)),
        );
      },
    );
  });
}
