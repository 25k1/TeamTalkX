@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

import 'support/e2e_server.dart';

Matcher _serverError(ServerError error) =>
    isA<TtCommandError>().having((e) => e.number, 'number', error.code);

void main() {
  group('messaging', skip: e2eSkip, () {
    test('channel and private messages reach the other user', () async {
      final alice = await loginAs(E2eAccount.alice);
      final bob = await loginAs(E2eAccount.bob);
      await bob.joinChannel(E2eChannel.root);

      final joined = nextEvent<UserJoinedEvent>(
        bob,
        (e) => e.user.id == alice.state.myUserId,
      );
      await alice.joinChannel(E2eChannel.root);
      expect((await joined).user.channelId, E2eChannel.root);

      final text = uniqueName('hello');
      final channelMessage = nextEvent<UserTextMessageEvent>(
        bob,
        (e) => e.message.text == text,
      );
      await alice.sendChannelMessage(E2eChannel.root, text);
      final received = (await channelMessage).message;
      expect(received.type, TtMsgType.channel);
      expect(received.fromUserId, alice.state.myUserId);
      expect(received.channelId, E2eChannel.root);

      final private = nextEvent<UserTextMessageEvent>(
        bob,
        (e) => e.message.type == TtMsgType.user,
      );
      await alice.sendUserMessage(bob.state.myUserId, 'psst');
      expect((await private).message.text, 'psst');
    });

    test('a long message arrives whole, split and put back', () async {
      final alice = await loginAs(E2eAccount.alice);
      final bob = await loginAs(E2eAccount.bob);
      final text = '${uniqueName('long')} ${'ქართული ტექსტი ' * 50}';
      final private = nextEvent<UserTextMessageEvent>(
        bob,
        (e) => e.message.type == TtMsgType.user,
      );
      await alice.sendUserMessage(bob.state.myUserId, text);
      final received = (await private).message;
      expect(received.text, text);
      expect(received.more, isFalse);
    });

    test('a password-protected channel needs its password', () async {
      final alice = await loginAs(E2eAccount.alice);

      await expectLater(
        alice.joinChannel(E2eChannel.locked, password: 'wrong'),
        throwsA(_serverError(ServerError.incorrectChannelPassword)),
      );

      final joined = nextEvent<UserJoinedEvent>(
        alice,
        (e) => e.user.id == alice.state.myUserId,
      );
      await alice.joinChannel(
        E2eChannel.locked,
        password: E2eChannel.lockedPassword,
      );
      expect((await joined).user.channelId, E2eChannel.locked);
    });

    test('the server enforces user rights', () async {
      final restricted = await loginAs(E2eAccount.restricted);
      expect(restricted.state.myUserRights, UserRights.none);
      await restricted.joinChannel(E2eChannel.root);

      await expectLater(
        restricted.sendChannelMessage(E2eChannel.root, 'not allowed'),
        throwsA(_serverError(ServerError.notAuthorized)),
      );
      await expectLater(
        restricted.saveChannel(
          TtChannelConfig(name: uniqueName('nope'), maxUsers: 5),
          parentId: E2eChannel.root,
        ),
        throwsA(_serverError(ServerError.notAuthorized)),
      );
    });
  });
}
