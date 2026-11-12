@Tags(['e2e'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';

import '../support/fake_platform.dart';
import 'support/e2e_server.dart';

Future<ProviderContainer> _app() async {
  SharedPreferences.setMockInitialValues({
    'speech_output': 'tts',
    'app_language': 'english',
  });
  final prefs = await SharedPreferences.getInstance();
  final platform = FakePlatform();
  final c = ProviderContainer(
    overrides: [
      ...platform.overrides,
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(() async {
    c.dispose();
    await platform.dispose();
  });
  c.listen(connectionProvider, (_, _) {});
  return c;
}

ServerEntry _alice() => ServerEntry(
  host: e2eHost,
  tcpPort: e2ePort,
  udpPort: e2ePort,
  username: E2eAccount.alice.username,
  password: E2eAccount.alice.password,
  nickname: uniqueName('alice'),
);

Future<T> _until<T extends ConnectionState>(ProviderContainer c) async {
  final deadline = DateTime.now().add(e2eTimeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = c.read(connectionProvider);
    if (state is T) return state;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('The session never reached $T');
}

void main() {
  group('session', skip: e2eSkip, () {
    test('connects, joins the root channel and disconnects', () async {
      final c = await _app();
      final session = c.read(connectionProvider.notifier);

      await session.connect(_alice());
      expect(c.read(connectionProvider), isA<LoggedIn>());
      final client = c.read(teamTalkClientProvider);
      final deadline = DateTime.now().add(e2eTimeout);
      while (client.state.joinedChannelId != E2eChannel.root &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(client.state.joinedChannelId, E2eChannel.root);

      await session.disconnect();
      expect(c.read(connectionProvider), isA<Disconnected>());
    });

    test('a server kick ends the session for good', () async {
      final c = await _app();
      final session = c.read(connectionProvider.notifier);
      await session.connect(_alice());
      final myId = c.read(teamTalkClientProvider).myUserId;

      final admin = await loginAs(E2eAccount.admin, nickname: 'Moderator');
      await admin.kickUser(myId);

      final ended = await _until<Disconnected>(c);
      expect((ended.reason! as KickedFromServer).by, 'Moderator');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(c.read(connectionProvider), isA<Disconnected>());
    });

    test('a wrong password fails the connect without retrying', () async {
      final c = await _app();
      final session = c.read(connectionProvider.notifier);

      await expectLater(
        session.connect(_alice().copyWith(password: 'wrong')),
        throwsA(anything),
      );
      final ended = c.read(connectionProvider) as Disconnected;
      expect(ended.reason, isA<ConnectFailed>());
    });
  });
}
