import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/app_info.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/pure_teamtalk_client.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the pure client is built with the app version from the provider',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appVersionProvider.overrideWithValue('9.8.7'),
        ],
      );
      addTearDown(container.dispose);

      final client = container.read(teamTalkClientProvider);

      expect(client, isA<PureTeamTalkClient>());
      expect((client as PureTeamTalkClient).appVersion, '9.8.7');
    },
  );

  test('login reports the given client version to the server', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final login = Completer<TtCommand>();
    server.listen((socket) {
      socket.done.ignore();
      socket.write('teamtalk userid=1 protocol="5.14"\r\n');
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final cmd = TtCommand.parse(line);
            if (cmd.verb != 'login') return;
            login.complete(cmd);
            final id = cmd.getInt('id');
            socket.write(
              'begin id=$id\r\n'
              'accepted userid=7 usertype=1\r\n'
              'end id=$id\r\n',
            );
          }, onError: (Object _) {});
    });

    final proto = ProtocolClient();
    addTearDown(proto.dispose);
    await proto.connect(host: '127.0.0.1', tcpPort: server.port);
    await proto.login(
      nickname: 'n',
      username: '',
      password: '',
      version: '9.8.7',
    );

    final cmd = await login.future;
    expect(cmd.getString('version'), '9.8.7');
  });
}
