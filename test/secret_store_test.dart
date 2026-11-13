import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/security/secrets.dart';
import 'package:teamtalkx/src/app/servers/bearware_login.dart';
import 'package:teamtalkx/src/app/servers/server_list_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/data/secret_store.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/platform/secret_cipher.dart';

class _FakeCipher implements SecretCipher {
  bool available = true;
  String keyId = 'k1';

  @override
  Future<String> encrypt(String text) async {
    if (!available) throw const SecretCipherUnavailable();
    return '$keyId:${base64Encode(utf8.encode(text).reversed.toList())}';
  }

  @override
  Future<String> decrypt(String data) async {
    if (!available) throw const SecretCipherUnavailable();
    final [key, body] = data.split(':');
    if (key != keyId) throw const SecretUndecryptable();
    return utf8.decode(base64Decode(body).reversed.toList());
  }
}

void main() {
  late Directory dir;
  late File file;
  late _FakeCipher cipher;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ttx-secrets');
    file = File('${dir.path}/secrets.json');
    cipher = _FakeCipher();
  });
  tearDown(() => dir.delete(recursive: true));

  group('SecretStore', () {
    test('saves encrypted and reads it back', () async {
      final store = await SecretStore.open(file, cipher);
      expect(store.read('a'), isNull);
      await store.writeAll({'a': 'hunter2', 'b': 'swordfish'});
      expect(store.encrypted, isTrue);
      final content = await file.readAsString();
      expect(content, isNot(contains('hunter2')));
      expect(jsonDecode(content), containsPair('keystore', isA<String>()));

      final again = await SecretStore.open(file, cipher);
      expect(again.read('a'), 'hunter2');
      expect(again.read('b'), 'swordfish');
    });

    test('without a Keystore it saves plain JSON', () async {
      cipher.available = false;
      final store = await SecretStore.open(file, cipher);
      await store.write('a', 'hunter2');
      expect(store.encrypted, isFalse);
      expect(jsonDecode(await file.readAsString()), {
        'version': 1,
        'plain': {'a': 'hunter2'},
      });
      expect((await SecretStore.open(file, cipher)).read('a'), 'hunter2');

      cipher.available = true;
      final later = await SecretStore.open(file, cipher);
      await later.write('b', 'x');
      expect(jsonDecode(await file.readAsString()), contains('keystore'));
      expect((await SecretStore.open(file, cipher)).read('a'), 'hunter2');
    });

    test("another device's secrets are dropped", () async {
      await (await SecretStore.open(file, cipher)).write('a', 'hunter2');
      cipher.keyId = 'k2';
      final store = await SecretStore.open(file, cipher);
      expect(store.read('a'), isNull);
      expect(await file.exists(), isFalse);
    });

    test('a damaged file is dropped', () async {
      await file.writeAsString('{not json');
      expect((await SecretStore.open(file, cipher)).read('a'), isNull);
      expect(await file.exists(), isFalse);
    });

    test('removing every secret removes the file', () async {
      final store = await SecretStore.open(file, cipher);
      await store.write('a', 'hunter2');
      await store.write('a', null);
      expect(await file.exists(), isFalse);
    });
  });

  group('migration from plaintext', () {
    const legacy = [
      ServerEntry(
        name: 'Home',
        host: 'tt.example',
        username: 'me',
        password: 'hunter2',
        channel: '/Room/',
        channelPassword: 'door',
      ),
      ServerEntry(name: 'Open', host: 'open.example'),
      ServerEntry(
        name: 'Home again',
        host: 'tt.example',
        username: 'me',
        password: 'other',
      ),
    ];

    Future<ProviderContainer> start(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final shared = await SharedPreferences.getInstance();
      final store = await SecretStore.open(file, cipher);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(shared),
          secretStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('server passwords move to the secret store', () async {
      var c = await start({'server_list': ServerEntry.encodeList(legacy)});
      final entries = await c.read(serverListProvider.future);
      expect(entries.map((e) => e.password), ['hunter2', '', 'other']);
      expect(entries.first.channelPassword, 'door');

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('server_list')!;
      expect(saved, isNot(contains('hunter2')));
      expect(saved, isNot(contains('door')));
      expect(await file.readAsString(), isNot(contains('hunter2')));

      c.dispose();
      c = await start({'server_list': saved});
      final again = await c.read(serverListProvider.future);
      expect(again.map((e) => e.password), ['hunter2', '', 'other']);
      expect(again.first.channelPassword, 'door');
    });

    test('a restore without the secrets keeps the servers', () async {
      final c = await start({'server_list': ServerEntry.encodeList(legacy)});
      final saved = (await c.read(serverListProvider.future)).length;
      c.dispose();
      await file.delete();

      final prefs = await SharedPreferences.getInstance();
      final restored = await start({
        'server_list': prefs.getString('server_list')!,
      });
      final entries = await restored.read(serverListProvider.future);
      expect(entries, hasLength(saved));
      expect(entries.every((e) => e.password.isEmpty), isTrue);
    });

    test('editing a server saves its password as a secret', () async {
      final c = await start(const {});
      await c.read(serverListProvider.future);
      await c
          .read(serverListProvider.notifier)
          .add(const ServerEntry(host: 'new.example', password: 'pw'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server_list'), isNot(contains('"pw"')));
      expect(c.read(serverListProvider).value!.single.password, 'pw');
      expect(
        (await SecretStore.open(file, cipher)).read('servers'),
        contains('"pw"'),
      );
    });

    test('the BearWare token moves to the secret store', () async {
      final c = await start({
        'bearware_username': 'me@bearware.dk',
        'bearware_token': 'tok',
      });
      final account = c.read(bearwareAccountProvider);
      expect(account.token, 'tok');
      expect(account.isLinked, isTrue);
      await c.read(secretStoreProvider).flush();
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bearware_token'), isNull);
      expect(
        (await SecretStore.open(file, cipher)).read('bearware_token'),
        'tok',
      );

      c.read(bearwareAccountProvider.notifier).reset();
      await c.read(secretStoreProvider).flush();
      expect(
        (await SecretStore.open(file, cipher)).read('bearware_token'),
        isNull,
      );
    });
  });
}
