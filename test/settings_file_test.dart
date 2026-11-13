import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/security/secrets.dart';
import 'package:teamtalkx/src/app/servers/bearware_login.dart';
import 'package:teamtalkx/src/app/servers/server_list_providers.dart';
import 'package:teamtalkx/src/app/settings/event_config.dart';
import 'package:teamtalkx/src/app/settings/settings_file.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/data/secret_store.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';

Future<ProviderContainer> _device(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(shared),
      secretStoreProvider.overrideWithValue(SecretStore.memory()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  Future<String> exportFrom({String? passphrase}) async {
    final a = await _device({
      'output_volume_percent': 70,
      'event.userJoined.interrupt': true,
      'media_key_bindings': 'next.single=nextChannel',
      'sound_pack_folder': 'content://this-device-only',
      'bearware_username': 'me@bearware.dk',
    });
    await a.read(serverListProvider.future);
    await a
        .read(serverListProvider.notifier)
        .add(
          const ServerEntry(
            name: 'Home',
            host: 'home.example',
            username: 'me',
            password: 'hunter2',
          ),
        );
    await a
        .read(serverListProvider.notifier)
        .add(const ServerEntry(name: 'Shared', host: 'shared.example'));
    a
        .read(bearwareAccountProvider.notifier)
        .save(const BearwareAccount(username: 'me@bearware.dk', token: 'tok'));
    return a
        .read(settingsFileProvider)
        .export(appVersion: '1.5.0', passphrase: passphrase);
  }

  test('without a passphrase there are no passwords in the file', () async {
    final text = await exportFrom();
    expect(text, isNot(contains('hunter2')));
    expect(text, isNot(contains('"tok"')));
    expect(text, isNot(contains('this-device-only')), reason: 'device only');
    final file = SettingsFile.parse(text);
    expect(file.passwords, isNull);
    expect(file.preferences['output_volume_percent'], 70);
    expect(file.servers.map((s) => s.host), ['home.example', 'shared.example']);
  });

  test(
    'import replaces settings and adds new servers with passwords',
    () async {
      final text = await exportFrom(passphrase: 'correct horse');
      expect(text, isNot(contains('hunter2')));
      final file = SettingsFile.parse(text);

      final b = await _device({'output_volume_percent': 30});
      await b.read(serverListProvider.future);
      await b
          .read(serverListProvider.notifier)
          .add(
            const ServerEntry(
              name: 'Mine',
              host: 'shared.example',
              password: 'keep',
            ),
          );
      expect(b.read(playbackSettingsProvider).masterVolumePercent, 30);

      final service = b.read(settingsFileProvider);
      await expectLater(
        service.openPasswords(file, 'wrong'),
        throwsA(isA<SettingsPassphraseWrong>()),
      );
      final passwords = await service.openPasswords(file, 'correct horse');
      final preview = await service.preview(file);
      expect(preview.newServers, 1);
      expect(preview.knownServers, 1);

      await service.apply(file, passwords: passwords);
      expect(b.read(playbackSettingsProvider).masterVolumePercent, 70);
      expect(b.read(keySettingsProvider).keyBindings.isEmpty, isFalse);
      expect(
        b.read(eventConfigProvider)[AppEvent.userJoined]!.interrupts,
        isTrue,
      );
      final servers = b.read(serverListProvider).value!;
      expect(servers.map((s) => s.name), ['Mine', 'Home']);
      expect(servers.first.password, 'keep', reason: 'mine stays as it is');
      expect(servers.last.password, 'hunter2');
      expect(b.read(bearwareAccountProvider).token, 'tok');
    },
  );

  test('not a settings file, or a newer one', () {
    expect(
      () => SettingsFile.parse('{"servers": []}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SettingsFile.parse(
        jsonEncode({'format': SettingsFile.format, 'version': 2}),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SettingsFile.parse('not json'),
      throwsA(isA<FormatException>()),
    );
  });
}
