import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/files/file_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

class _Client extends FakeVoiceClient {
  final started = <String>[];
  final info = <int, TtFileTransfer>{};

  @override
  Future<void> recvFile(int channelId, int fileId, String localPath) async =>
      started.add('down $fileId');

  @override
  Future<void> sendFile(int channelId, String localPath) async =>
      started.add('up $localPath');

  @override
  TtFileTransfer? getFileTransferInfo(int transferId) => info[transferId];
}

TtRemoteFile _file(int id) => TtRemoteFile(
  channelId: 1,
  fileId: id,
  fileName: 'f$id.txt',
  fileSize: 100,
  username: '',
  uploadTime: '',
);

TtFileTransfer _transfer(
  int id,
  TtFileTransferStatus status, {
  int transferred = 0,
  String path = '',
}) => TtFileTransfer(
  status: status,
  transferId: id,
  channelId: 1,
  localFilePath: path,
  remoteFileName: 'f$id.txt',
  fileSize: 100,
  transferred: transferred,
  inbound: true,
);

void main() {
  late FakePlatform platform;
  late _Client client;
  late ProviderContainer c;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {'speech_output': 'tts'});
    final prefs = await SharedPreferences.getInstance();
    platform = FakePlatform();
    client = _Client();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamTalkClientProvider.overrideWithValue(client),
      ],
    );
    c
      ..listen(fileTransfersProvider, (_, _) {})
      ..listen(transferQueueProvider, (_, _) {});
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    });
  });

  Future<void> emit(TtFileTransfer t) async {
    client.eventController.add(FileTransferEvent(t));
    await pumpEventQueue();
  }

  test('two at a time; the next starts when one ends (D67)', () async {
    final queue = c.read(transferQueueProvider.notifier);
    expect(queue.download(_file(1), 'a'), isFalse);
    expect(queue.download(_file(2), 'b'), isFalse);
    expect(queue.download(_file(3), 'c'), isTrue, reason: 'waits');
    expect(queue.upload(1, 'up.txt', 'up.txt'), isTrue);
    await pumpEventQueue();
    expect(client.started, ['down 1', 'down 2']);
    expect(c.read(transferQueueProvider).map((q) => q.name), [
      'f3.txt',
      'up.txt',
    ]);

    await emit(_transfer(10, TtFileTransferStatus.active));
    await emit(_transfer(11, TtFileTransferStatus.active));
    expect(client.started, hasLength(2));

    await emit(_transfer(10, TtFileTransferStatus.error));
    expect(client.started, ['down 1', 'down 2', 'down 3']);

    queue.cancel(c.read(transferQueueProvider).single.id);
    expect(c.read(transferQueueProvider), isEmpty);
  });

  test('progress is spoken at each quarter', () async {
    await emit(_transfer(5, TtFileTransferStatus.active));
    client.info[5] = _transfer(5, TtFileTransferStatus.active, transferred: 30);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(platform.tts.spoken, contains('f5.txt, 25%'));
    client.info[5] = _transfer(5, TtFileTransferStatus.active, transferred: 80);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(platform.tts.spoken, contains('f5.txt, 75%'));
    expect(
      platform.tts.spoken.where((t) => t.startsWith('f5.txt')),
      hasLength(2),
      reason: 'not every step',
    );
  });

  test('a saved download is offered to open (D68)', () async {
    final temp = await Directory.systemTemp.createTemp('ttx');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final dir = await Directory(
      '${temp.path}/downloads/1',
    ).create(recursive: true);
    final file = await File('${dir.path}/f7.txt').writeAsString('x');
    final saved = c.read(fileTransfersProvider.notifier).saved.first;
    await emit(
      _transfer(
        7,
        TtFileTransferStatus.finished,
        transferred: 100,
        path: file.path,
      ),
    );
    final download = await saved;
    expect(download.name, 'f7.txt');
    expect(download.path, 'Download/TeamTalkX/f7.txt');
    expect(download.uri, 'content://downloads/f7.txt');
  });
}
