import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';

import '../../test/e2e/support/e2e_server.dart';

void main() {
  test('a long message through the real server', () async {
    final alice = await loginAs(E2eAccount.alice);
    final bob = await loginAs(E2eAccount.bob);
    await alice.joinChannel(E2eChannel.root);
    await bob.joinChannel(E2eChannel.root);

    final text = 'ა' * 1500;
    final received = nextEvent<UserTextMessageEvent>(
      bob,
      (e) => e.message.fromUserId == alice.state.myUserId,
    );
    await alice.sendChannelMessage(E2eChannel.root, text);
    final got = (await received).message;
    debugPrint(
      'sent ${utf8.encode(text).length} bytes, '
      'received ${utf8.encode(got.text).length} bytes, more=${got.more}',
    );
  }, skip: e2eSkip);
}
