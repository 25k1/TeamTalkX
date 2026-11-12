import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/recording/recording_controller.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/recorder.dart';
import 'package:teamtalkx/src/audio/recording_writers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/recording.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/platform/recording_folder.dart';
import 'package:teamtalkx/src/ui/settings/recording_settings.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';
import 'support/localized_app.dart';

class _Collect implements RecordingWriter {
  final samples = <int>[];
  int syncs = 0;
  bool closed = false;

  @override
  void write(Int16List pcm) => samples.addAll(pcm);
  @override
  void sync() => syncs++;
  @override
  void close() => closed = true;

  List<int> get left => [
    for (var i = 0; i < samples.length; i += 2) samples[i],
  ];
}

Int16List _tone(int frames, int value) =>
    Int16List(frames * 2)..fillRange(0, frames * 2, value);

class _Page {
  _Page(this.flags, this.granule, this.sequence, this.packets, this.crcOk);
  final int flags;
  final int granule;
  final int sequence;
  final List<Uint8List> packets;
  final bool crcOk;
}

List<_Page> _readPages(Uint8List bytes) {
  final pages = <_Page>[];
  var at = 0;
  while (at < bytes.length) {
    expect(String.fromCharCodes(bytes.sublist(at, at + 4)), 'OggS');
    final b = ByteData.sublistView(bytes, at);
    final segments = b.getUint8(26);
    final lacing = bytes.sublist(at + 27, at + 27 + segments);
    final length = 27 + segments + lacing.fold<int>(0, (n, l) => n + l);
    final page = Uint8List.fromList(bytes.sublist(at, at + length));
    final crc = ByteData.sublistView(page).getUint32(22, Endian.little);
    page.setRange(22, 26, const [0, 0, 0, 0]);
    final packets = <Uint8List>[];
    var data = at + 27 + segments;
    var packet = <int>[];
    for (final l in lacing) {
      packet.addAll(bytes.sublist(data, data + l));
      data += l;
      if (l < 255) {
        packets.add(Uint8List.fromList(packet));
        packet = [];
      }
    }
    pages.add(
      _Page(
        b.getUint8(5),
        b.getInt64(6, Endian.little),
        b.getUint32(18, Endian.little),
        packets,
        oggCrc(page) == crc,
      ),
    );
    at += length;
  }
  return pages;
}

class _Connection extends SessionController {
  _Connection(this._initial);
  final ConnectionState _initial;
  @override
  ConnectionState build() => _initial;
  void set(ConnectionState s) => state = s;
}

class _RecordingClient extends FakeVoiceClient {
  String? directory;
  RecordingMode? mode;
  RecordingFormat? format;
  List<int> users = const [7, 9];
  bool fail = false;
  int stops = 0;

  @override
  Future<void> startRecording({
    required String directory,
    required RecordingMode mode,
    required RecordingFormat format,
  }) async {
    if (fail) throw const RecordingFailed();
    this.directory = directory;
    this.mode = mode;
    this.format = format;
  }

  @override
  bool get isRecording => directory != null;

  @override
  Future<void> stopRecording() async {
    stops++;
    final dir = directory;
    if (dir == null) return;
    final ids = mode == RecordingMode.mixed ? [mixedRecordingUserId] : users;
    for (final id in ids) {
      File(
        '$dir/${recordingFileName(id, format!)}',
      ).writeAsBytesSync([1, 2, 3]);
    }
    directory = null;
  }
}

TtUser _user(int id, String nickname) => TtUser(
  id: id,
  username: '',
  nickname: nickname,
  statusMessage: '',
  channelId: 1,
  userState: 0,
  userType: 1,
  clientName: '',
);

TtChannel _channel({bool noRecording = false}) => TtChannel(
  id: 1,
  parentId: 5,
  name: 'Lobby',
  topic: '',
  hasPassword: false,
  maxUsers: 10,
  channelType: noRecording ? ChannelTypes.noRecording : 0,
);

void main() {
  group('WAV', () {
    test('the header describes 48 kHz 16-bit stereo', () {
      final h = ByteData.sublistView(wavHeader(1000));
      expect(String.fromCharCodes(wavHeader(1000).sublist(0, 4)), 'RIFF');
      expect(h.getUint32(4, Endian.little), 1036);
      expect(h.getUint16(22, Endian.little), 2);
      expect(h.getUint32(24, Endian.little), 48000);
      expect(h.getUint32(28, Endian.little), 192000);
      expect(h.getUint16(34, Endian.little), 16);
      expect(h.getUint32(40, Endian.little), 1000);
    });

    test('the sizes are right after each sync, so a killed recording '
        'still plays', () {
      final dir = Directory.systemTemp.createTempSync('ttx_wav');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/a.wav';
      final w = WavWriter(path)
        ..write(_tone(480, 1000))
        ..sync();
      final synced = File(path).readAsBytesSync();
      expect(synced.length, 44 + 480 * 4);
      expect(
        ByteData.sublistView(synced).getUint32(40, Endian.little),
        480 * 4,
      );
      w
        ..write(_tone(480, -1000))
        ..close();
      final bytes = File(path).readAsBytesSync();
      final b = ByteData.sublistView(bytes);
      expect(b.getUint32(40, Endian.little), 960 * 4);
      expect(b.getInt16(44, Endian.little), 1000);
      expect(b.getInt16(44 + 480 * 4, Endian.little), -1000);
    });
  });

  group('Ogg Opus', () {
    test('the page checksum is Ogg\'s CRC-32', () {
      expect(oggCrc(Uint8List.fromList('123456789'.codeUnits)), 0x89A1897F);
    });

    test('headers, then audio pages, the last ending at the exact '
        'length (RFC 7845)', () {
      final dir = Directory.systemTemp.createTempSync('ttx_ogg');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/a.ogg';
      var encoded = 0;
      var closed = false;
      final w = OggOpusWriter(
        path,
        encode: (frame) {
          expect(frame.length, 960 * 2);
          encoded++;
          return Uint8List.fromList(List.filled(300, encoded));
        },
        onClose: () => closed = true,
        serial: 42,
      );
      w
        ..write(_tone(72000, 100))
        ..write(_tone(100, 100))
        ..close();
      expect(closed, isTrue);

      final pages = _readPages(File(path).readAsBytesSync());
      expect(pages.every((p) => p.crcOk), isTrue);
      expect(
        [for (final p in pages) p.sequence],
        [for (var i = 0; i < pages.length; i++) i],
      );
      expect(pages.first.flags, 0x02, reason: 'beginning of stream');
      expect(
        String.fromCharCodes(pages[0].packets.single.sublist(0, 8)),
        'OpusHead',
      );
      final head = ByteData.sublistView(pages[0].packets.single);
      expect(head.getUint8(9), 2);
      expect(head.getUint16(10, Endian.little), 312);
      expect(head.getUint32(12, Endian.little), 48000);
      expect(
        String.fromCharCodes(pages[1].packets.single.sublist(0, 8)),
        'OpusTags',
      );

      final audio = pages.sublist(2);
      final packets = [for (final p in audio) ...p.packets];
      expect(packets, hasLength(76));
      expect(packets.every((p) => p.length == 300), isTrue);
      expect(audio.first.granule, 50 * 960);
      expect(audio.last.flags, 0x04, reason: 'end of stream');
      expect(audio.last.granule, 312 + 72100);
    });

    test('sync writes a page only once half a second is waiting', () {
      final dir = Directory.systemTemp.createTempSync('ttx_sync');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/a.ogg';
      final w = OggOpusWriter(path, encode: (_) => Uint8List(3), serial: 1);
      final headers = File(path).lengthSync();
      w
        ..write(_tone(4800, 0))
        ..sync();
      expect(File(path).lengthSync(), headers, reason: '100 ms waits');
      w
        ..write(_tone(19200, 0))
        ..sync();
      expect(File(path).lengthSync(), greaterThan(headers));
      w.close();
    });

    test('the native encoder makes a file that ends where the audio does', () {
      final dir = Directory.systemTemp.createTempSync('ttx_opus');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/a.ogg';
      final OggOpusWriter w;
      try {
        w = OggOpusWriter.withOpus(path);
      } on Object {
        markTestSkipped('No native Opus here');
        return;
      }
      final sine = Int16List(48000 * 2);
      for (var i = 0; i < 48000; i++) {
        sine[i * 2] = sine[i * 2 + 1] =
            (math.sin(i * 2 * math.pi * 440 / 48000) * 8000).round();
      }
      w
        ..write(sine)
        ..close();
      final pages = _readPages(File(path).readAsBytesSync());
      expect(pages.every((p) => p.crcOk), isTrue);
      expect(pages.last.granule, 312 + 48000);
      expect(pages.last.flags & 0x04, 0x04);
    });
  });

  group('Recorder', () {
    late Map<int, _Collect> files;
    Recorder recorder(RecordingMode mode) {
      files = {};
      return Recorder(
        mode: mode,
        startUs: 0,
        open: (userId) => files[userId] = _Collect(),
      );
    }

    test('streams playing together are mixed', () {
      final r = recorder(RecordingMode.mixed)
        ..add((8 << 8) | 1, _tone(960, 1000), 0)
        ..add((9 << 8) | 1, _tone(960, 500), 0)
        ..add((9 << 8) | 1, _tone(960, 500), 20000);
      while (!r.finish(40000)) {}
      final mixed = files[mixedRecordingUserId]!;
      expect(mixed.closed, isTrue);
      expect(mixed.left.take(960), everyElement(1500));
      expect(mixed.left.skip(960).take(960), everyElement(500));
    });

    test('a stream continues where it left off, and starts again at the '
        'clock after a pause', () {
      final r = recorder(RecordingMode.mixed)
        ..add((8 << 8) | 1, _tone(960, 1000), 0)
        ..add((8 << 8) | 1, _tone(960, 2000), 5000)
        ..add((8 << 8) | 1, _tone(960, 3000), 1000000);
      while (!r.finish(1100000)) {}
      final left = files[mixedRecordingUserId]!.left;
      expect(left[0], 1000);
      expect(left[960], 2000);
      expect(left[1920], 0, reason: 'silence between');
      expect(left[48000], 3000);
    });

    test('loud streams are clipped, not wrapped', () {
      final r = recorder(RecordingMode.mixed)
        ..add(1 << 8, _tone(960, 30000), 0)
        ..add(2 << 8, _tone(960, 30000), 0);
      while (!r.finish(20000)) {}
      expect(files[mixedRecordingUserId]!.left.first, 32767);
    });

    test('per user, every file starts at the start of the recording', () {
      final r = recorder(RecordingMode.perUser)
        ..add((8 << 8) | 1, _tone(960, 1000), 0)
        ..add((9 << 8) | 1, _tone(960, 700), 1000000)
        ..add((9 << 8) | 4, _tone(960, 300), 1000000);
      while (!r.finish(1020000)) {}
      final eight = files[8]!.left;
      final nine = files[9]!.left;
      expect(nine.length, eight.length, reason: 'the files line up');
      expect(nine.take(48000), everyElement(0));
      expect(nine[48000], 1000);
      expect(eight[0], 1000);
    });

    test('ticks write only what can no longer change', () {
      final r = recorder(RecordingMode.mixed)
        ..add(1 << 8, _tone(960, 1000), 0)
        ..tick(400000);
      final mixed = files[mixedRecordingUserId]!;
      expect(mixed.samples, isEmpty, reason: 'held for 500 ms');
      r.tick(1000000);
      expect(mixed.samples.length, 24000 * 2);
      expect(mixed.syncs, 1);
    });

    test('a file that starts late catches up a few seconds per tick', () {
      final r = recorder(RecordingMode.perUser)
        ..add(8 << 8, _tone(960, 1000), 60000000)
        ..tick(60000000);
      expect(
        files[8]!.samples.length,
        RecordingTimeline.maxBlocksPerFlush * 960 * 2,
      );
      var steps = 1;
      while (!r.finish(60100000)) {
        steps++;
      }
      expect(steps, greaterThan(1));
      expect(files[8]!.left[60 * 48000], 1000);
    });

    test('a file that cannot be opened is left out', () {
      final failed = <int>[];
      final r = Recorder(
        mode: RecordingMode.perUser,
        startUs: 0,
        open: (userId) => userId == 9
            ? throw const FileSystemException('denied')
            : (files[userId] = _Collect()),
        onWriterFailed: (userId, _) => failed.add(userId),
      );
      files = {};
      r
        ..add(9 << 8, _tone(960, 1), 0)
        ..add(9 << 8, _tone(960, 1), 20000)
        ..add(8 << 8, _tone(960, 1), 0);
      expect(failed, [9], reason: 'tried once');
      expect(r.users, [8]);
    });
  });

  group('AudioWorker recording', () {
    test('a WAV recording is closed by stop, and by shutdown', () async {
      final dir = Directory.systemTemp.createTempSync('ttx_rec');
      addTearDown(() => dir.deleteSync(recursive: true));
      final worker = await AudioWorker.spawn(onTx: (_) {});
      expect(
        await worker.startRecording(
          directory: dir.path,
          mode: RecordingMode.mixed,
          format: RecordingFormat.wav,
        ),
        isNull,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await worker.stopRecording();
      final file = File('${dir.path}/mixed.wav');
      final bytes = file.readAsBytesSync();
      final dataBytes = ByteData.sublistView(
        bytes,
      ).getUint32(40, Endian.little);
      expect(dataBytes, bytes.length - 44);
      expect(dataBytes, greaterThan(0), reason: 'silence for the 300 ms');

      final second = Directory('${dir.path}/2')..createSync();
      await worker.startRecording(
        directory: second.path,
        mode: RecordingMode.mixed,
        format: RecordingFormat.wav,
      );
      await worker.shutdown();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(File('${second.path}/mixed.wav').existsSync(), isTrue);
    });

    test('a folder that does not exist is refused', () async {
      final worker = await AudioWorker.spawn(onTx: (_) {});
      addTearDown(worker.shutdown);
      expect(
        await worker.startRecording(
          directory: '${Directory.systemTemp.path}/ttx-missing/x/y',
          mode: RecordingMode.mixed,
          format: RecordingFormat.wav,
        ),
        isNotNull,
      );
    });
  });

  group('RecordingController', () {
    late ProviderContainer c;
    late FakePlatform platform;
    late _RecordingClient client;
    late Directory cache;

    Future<void> setUp0({
      Map<String, Object> prefs = const {},
      bool noRecording = false,
    }) async {
      SharedPreferences.setMockInitialValues({
        'speech_output': 'tts',
        ...prefs,
      });
      final shared = await SharedPreferences.getInstance();
      cache = Directory.systemTemp.createTempSync('ttx_cache');
      platform = FakePlatform();
      client = _RecordingClient()..addMe();
      client.state
        ..apply(ChannelNewEvent(_channel(noRecording: noRecording)))
        ..apply(UserLoggedInEvent(_user(9, 'Ann')));
      c = ProviderContainer(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(shared),
          teamTalkClientProvider.overrideWithValue(client),
          connectionProvider.overrideWith(() => _Connection(const LoggedIn(7))),
          recordingCacheProvider.overrideWithValue(() async => cache),
        ],
      );
      c.listen(recordingProvider, (_, _) {});
      addTearDown(() async {
        c.dispose();
        await platform.dispose();
        await client.close();
        if (cache.existsSync()) cache.deleteSync(recursive: true);
      });
    }

    RecordingController controller() => c.read(recordingProvider.notifier);

    test('per user, the files are named after the time, the channel and '
        'each user, in the picked folder', () async {
      await setUp0(
        prefs: {
          'recording_mode': 'perUser',
          'recording_format': 'wav',
          'recording_folder': 'content://tree/rec',
          'recording_folder_name': 'Recordings',
        },
      );
      await controller().start();
      expect(c.read(recordingProvider), isA<RecordingActive>());
      expect(client.mode, RecordingMode.perUser);
      expect(client.format, RecordingFormat.wav);
      expect(platform.tts.spoken.last, 'Recording started');

      await controller().stop();
      expect(c.read(recordingProvider), isA<RecordingIdle>());
      final names = platform.recordingFolder.saved.keys.toList()..sort();
      expect(names, hasLength(2));
      expect(
        names[0],
        matches(RegExp(r'^\d{4}-\d\d-\d\d \d\d-\d\d-\d\d Lobby - Ann\.wav$')),
      );
      expect(names[1], endsWith('Lobby - me.wav'));
      expect(
        platform.tts.spoken.last,
        'Recording saved: 2 files in Recordings',
      );
      expect(cache.listSync(), isEmpty, reason: 'moved out of the cache');
    });

    test(
      'without a folder the mixed file goes to Download/TeamTalkX',
      () async {
        await setUp0();
        await controller().toggle();
        await controller().toggle();
        final name = platform.downloads.published.keys.single;
        expect(name, endsWith(' Lobby.ogg'));
        expect(
          platform.tts.spoken.last,
          'Recording saved in Download/TeamTalkX',
        );
      },
    );

    test('a folder that cannot be written falls back to '
        'Download/TeamTalkX', () async {
      await setUp0(
        prefs: {
          'recording_folder': 'content://tree/rec',
          'recording_folder_name': 'Recordings',
        },
      );
      platform.recordingFolder.writable = false;
      await controller().start();
      await controller().stop();
      expect(platform.downloads.published, hasLength(1));
    });

    test('a channel that forbids recording refuses it, and stops it when '
        'it starts to', () async {
      await setUp0(noRecording: true);
      await controller().start();
      expect(c.read(recordingProvider), isA<RecordingIdle>());
      expect(client.directory, isNull);
      expect(platform.tts.spoken.last, "This channel doesn't allow recording");

      client.state.apply(ChannelUpdateEvent(_channel()));
      await controller().start();
      expect(c.read(recordingProvider), isA<RecordingActive>());
      client.state.apply(ChannelUpdateEvent(_channel(noRecording: true)));
      await pumpEventQueue();
      expect(c.read(recordingProvider), isA<RecordingIdle>());
      expect(client.stops, 1);
      expect(
        platform.tts.spoken,
        contains("Recording stopped: this channel doesn't allow recording"),
      );
    });

    test('losing the connection stops and saves the recording', () async {
      await setUp0();
      await controller().start();
      (c.read(connectionProvider.notifier) as _Connection).set(
        const Disconnected(),
      );
      await pumpEventQueue();
      expect(c.read(recordingProvider), isA<RecordingIdle>());
      expect(platform.downloads.published, hasLength(1));
    });

    test('a recording that could not start says why', () async {
      await setUp0();
      client.fail = true;
      await controller().start();
      expect(c.read(recordingProvider), isA<RecordingIdle>());
      expect(
        platform.tts.spoken.last,
        "The recording file couldn't be created.",
      );
    });

    test('the settings are kept', () async {
      await setUp0();
      platform.recordingFolder.toPick = const PickedFolder(
        tree: 'content://tree/x',
        name: 'X',
      );
      final settings = c.read(recordingSettingsProvider.notifier)
        ..setMode(RecordingMode.perUser)
        ..setFormat(RecordingFormat.wav);
      expect(await settings.pickFolder(), isTrue);
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('recording_mode'), 'perUser');
      expect(prefs.getString('recording_format'), 'wav');
      expect(prefs.getString('recording_folder'), 'content://tree/x');
      await settings.clearFolder();
      expect(platform.recordingFolder.released, ['content://tree/x']);
      expect(c.read(recordingSettingsProvider).folder, isNull);
    });
  });

  testWidgets('Settings › Recording changes what is recorded and where', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_language': 'english'});
    final prefs = await SharedPreferences.getInstance();
    final platform = FakePlatform();
    addTearDown(platform.dispose);
    platform.recordingFolder.toPick = const PickedFolder(
      tree: 'content://tree/rec',
      name: 'Recordings',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const LocalizedTestApp(
          home: Scaffold(body: RecordingSettingsView()),
        ),
      ),
    );
    expect(find.text('Everyone in one file'), findsOneWidget);
    expect(find.text('Ogg Opus: small files'), findsOneWidget);
    expect(find.text('Download/TeamTalkX'), findsOneWidget);

    await tester.tap(find.text('What to record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A file for each user'));
    await tester.pumpAndSettle();
    expect(prefs.getString('recording_mode'), 'perUser');

    await tester.tap(find.text('Recordings folder'));
    await tester.pumpAndSettle();
    expect(find.text('Recordings are saved in Recordings'), findsOneWidget);
    expect(find.text('Save in Download/TeamTalkX instead'), findsOneWidget);
  });
}
