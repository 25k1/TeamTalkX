import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/files/file_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/settings/sound_packs.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/platform/sound_pack_folder.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

PackSoundFile _sound(String name) =>
    PackSoundFile(name: name, uri: 'content://tree/$name', modified: 1);

void main() {
  late FakePlatform platform;
  late FakeVoiceClient client;
  late ProviderContainer c;

  Future<void> setUpWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues({'speech_output': 'tts', ...prefs});
    final shared = await SharedPreferences.getInstance();
    platform = FakePlatform();
    client = FakeVoiceClient();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(shared),
        teamTalkClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    });
  }

  group('sound packs from a picked folder', () {
    test('without a folder only the built-in packs', () async {
      await setUpWith(const {});
      final packs = await c.read(soundPacksProvider.future);
      expect(packs.packs.map((p) => p.id), ['default', 'majorly']);
      expect(packs.folderUnreadable, isFalse);
    });

    test('a picked folder offers its packs, read in place', () async {
      await setUpWith(const {'sound_pack': 'dir:Classic'});
      platform.soundPackFolder
        ..toPick = const PickedFolder(tree: 'content://tree', name: 'sounds')
        ..packs = [
          PackFolderContents(
            name: 'Classic',
            sounds: [_sound('User_Join.ogg'), _sound('user_join.mp3')],
          ),
        ];
      c.listen(soundPacksProvider, (_, _) {});
      expect(
        await c.read(soundPackFolderSettingProvider.notifier).pick(),
        isTrue,
      );
      final packs = await c.read(soundPacksProvider.future);
      final classic = packs.packs.last;
      expect(classic.id, 'dir:Classic', reason: 'the old id carries over');
      expect(classic.kind, SoundPackKind.folder);

      final source = classic.sourceFor(SoundEvent.userJoin);
      expect(source, isA<FolderSound>());
      expect(
        (source! as FolderSound).file.name,
        'User_Join.ogg',
        reason: 'ogg before mp3, any case',
      );
      expect(classic.sourceFor(SoundEvent.userLeft), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sound_pack_folder'), 'content://tree');
    });

    test('a folder that can no longer be read is reported', () async {
      await setUpWith(const {
        'sound_pack_folder': 'content://tree',
        'sound_pack_folder_name': 'sounds',
      });
      platform.soundPackFolder.readable = false;
      final packs = await c.read(soundPacksProvider.future);
      expect(packs.folderUnreadable, isTrue);
      expect(packs.packs, hasLength(2));
    });

    test('another folder or none gives up the old access', () async {
      await setUpWith(const {
        'sound_pack_folder': 'content://old',
        'sound_pack_folder_name': 'old',
      });
      platform.soundPackFolder.toPick = const PickedFolder(
        tree: 'content://new',
        name: 'new',
      );
      await c.read(soundPackFolderSettingProvider.notifier).pick();
      expect(platform.soundPackFolder.released, ['content://old']);
      await c.read(soundPackFolderSettingProvider.notifier).clear();
      expect(platform.soundPackFolder.released, [
        'content://old',
        'content://new',
      ]);
      expect(c.read(soundPackFolderSettingProvider), isNull);
    });
  });

  group('downloads', () {
    test('a finished download moves to Download/TeamTalkX (D34)', () async {
      await setUpWith(const {});
      final temp = await Directory.systemTemp.createTemp('ttx');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final dir = await Directory(
        '${temp.path}/downloads/1',
      ).create(recursive: true);
      final file = await File('${dir.path}/notes.txt').writeAsString('hi');
      c.listen(fileTransfersProvider, (_, _) {});

      client.eventController.add(
        FileTransferEvent(
          TtFileTransfer(
            status: TtFileTransferStatus.finished,
            transferId: 5,
            channelId: 1,
            localFilePath: file.path,
            remoteFileName: 'notes.txt',
            fileSize: 2,
            transferred: 2,
            inbound: true,
          ),
        ),
      );
      await pumpEventQueue();

      expect(platform.downloads.published, {'notes.txt': file.path});
      final transfer = c.read(fileTransfersProvider)[5]!;
      expect(transfer.localFilePath, 'content://downloads/notes.txt');
      expect(
        c.read(fileTransfersProvider.notifier).savedPath(5),
        'Download/TeamTalkX/notes.txt',
      );
      expect(await dir.exists(), isFalse, reason: 'the cache copy is gone');
    });
  });
}
