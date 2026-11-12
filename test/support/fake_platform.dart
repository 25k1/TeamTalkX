import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:teamtalkx/src/app/platform_services.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/settings/sound_player.dart';
import 'package:teamtalkx/src/platform/app_updater.dart';
import 'package:teamtalkx/src/platform/audio_routing.dart';
import 'package:teamtalkx/src/platform/connectivity.dart';
import 'package:teamtalkx/src/platform/deep_links.dart';
import 'package:teamtalkx/src/platform/foreground_service.dart';
import 'package:teamtalkx/src/platform/interruptions.dart';
import 'package:teamtalkx/src/platform/media_keys.dart';
import 'package:teamtalkx/src/platform/native_export.dart';
import 'package:teamtalkx/src/platform/native_haptics.dart';
import 'package:teamtalkx/src/platform/native_hotkey.dart';
import 'package:teamtalkx/src/platform/native_pm_notifications.dart';
import 'package:teamtalkx/src/platform/native_tts.dart';
import 'package:teamtalkx/src/platform/permissions.dart';
import 'package:teamtalkx/src/platform/recording_folder.dart';
import 'package:teamtalkx/src/platform/sound_pack_folder.dart';

class FakeTts implements Tts {
  final spoken = <String>[];
  int stopped = 0;

  @override
  Future<bool> init({String engine = ''}) async => true;
  @override
  Future<List<TtsEngineInfo>> getEngines() async => const [];
  @override
  Future<List<String>> getLanguages() async => const [];
  @override
  Future<List<TtsVoiceInfo>> getVoices() async => const [];
  @override
  Future<void> configure({
    required String language,
    required String voice,
    required double rate,
    required double pitch,
    required double volume,
    required bool accessibilityStream,
  }) async {}
  @override
  Future<void> speak(String text, {bool interrupt = false}) async {
    spoken.add(text);
    if (interrupt) interrupted.add(text);
  }

  final interrupted = <String>[];
  @override
  Future<void> stop() async => stopped++;
}

class FakePmNotifications implements PmNotifications {
  final open = StreamController<int>.broadcast();
  final reply = StreamController<(int, String)>.broadcast();
  final shown = <(int, String, String)>[];
  final cancelled = <int>[];
  int launchedFor = 0;

  @override
  Stream<int> get openRequests => open.stream;
  @override
  Stream<(int, String)> get replies => reply.stream;
  @override
  Future<void> show({
    required int userId,
    required String title,
    required String message,
  }) async => shown.add((userId, title, message));
  @override
  Future<void> cancel(int userId) async => cancelled.add(userId);
  @override
  Future<int> initialPm() async => launchedFor;

  Future<void> close() async {
    await open.close();
    await reply.close();
  }
}

class FakeForegroundService implements ForegroundService {
  final action = StreamController<ForegroundAction>.broadcast();
  final calls = <String>[];

  @override
  Stream<ForegroundAction> get actions => action.stream;
  @override
  Future<void> start({
    required String serverName,
    required String channelName,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  }) async => calls.add('start $serverName${keepAwake ? ' awake' : ''}');
  @override
  Future<void> update({
    required String serverName,
    required String channelName,
    bool transmitting = false,
    bool recording = false,
    bool keepAwake = false,
  }) async => calls.add(
    'update $serverName tx=$transmitting${recording ? ' rec' : ''}'
    '${keepAwake ? ' awake' : ''}',
  );
  @override
  Future<void> stop() async => calls.add('stop');

  Future<void> close() async {
    await action.close();
  }
}

class FakeHaptics implements Haptics {
  final played = <List<int>>[];

  @override
  Future<bool> waveform(List<int> timings, List<int> amplitudes) async {
    played.add(timings);
    return true;
  }
}

class FakeHotkeys implements Hotkeys {
  final down = StreamController<void>.broadcast();
  final up = StreamController<void>.broadcast();
  final capture = StreamController<(int, String)>.broadcast();
  final pttKeys = <int>[];

  @override
  Stream<void> get pttDown => down.stream;
  @override
  Stream<void> get pttUp => up.stream;
  @override
  Stream<(int, String)> get captured => capture.stream;
  @override
  Future<void> setPttKey(int keyCode) async => pttKeys.add(keyCode);
  @override
  Future<void> startCapture() async {}
  @override
  Future<void> stopCapture() async {}

  Future<void> close() async {
    await down.close();
    await up.close();
    await capture.close();
  }
}

class FakeMediaKeys implements MediaKeys {
  final key = StreamController<({MediaKey key, bool down})>.broadcast(
    sync: true,
  );
  final configured = <({bool session, Set<MediaKey> mapped})>[];

  @override
  Stream<({MediaKey key, bool down})> get events => key.stream;
  @override
  Future<void> configure({
    required bool session,
    required Set<MediaKey> mapped,
  }) async => configured.add((session: session, mapped: mapped));

  void press(MediaKey k) {
    key
      ..add((key: k, down: true))
      ..add((key: k, down: false));
  }

  Future<void> close() => key.close();
}

class FakeInterruptions implements Interruptions {
  final call = StreamController<CallState>.broadcast();
  final otherPlaying = StreamController<bool>.broadcast();
  final focus = StreamController<FocusChange>.broadcast();
  final calls = <String>[];

  @override
  Stream<CallState> get callState => call.stream;
  @override
  Stream<bool> get otherAppPlaying => otherPlaying.stream;
  @override
  Future<void> start() async => calls.add('start');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> duckOthers({required bool voiceCall}) async =>
      calls.add('duckOthers');
  @override
  Future<void> stopDuckingOthers() async => calls.add('stopDuckingOthers');
  @override
  Stream<FocusChange> get focusChanges => focus.stream;

  Future<void> close() async {
    await call.close();
    await otherPlaying.close();
    await focus.close();
  }
}

class FakeDeepLinks implements DeepLinks {
  final link = StreamController<String>.broadcast();
  final file = StreamController<String>.broadcast();
  String? initialLink;
  String? initialFile;

  @override
  Stream<String> get links => link.stream;
  @override
  Stream<String> get files => file.stream;
  @override
  Future<String?> getInitialLink() async => initialLink;
  @override
  Future<String?> getInitialFile() async => initialFile;

  Future<void> close() async {
    await link.close();
    await file.close();
  }
}

class FakeDownloads implements Downloads {
  final saved = <String, String>{};

  final published = <String, String>{};
  final opened = <String>[];
  bool canOpen = true;

  @override
  Future<String> saveText(
    String fileName,
    String content, {
    String mimeType = '',
  }) async {
    saved[fileName] = content;
    return 'Download/TeamTalkX/$fileName';
  }

  @override
  Future<bool> exists(String fileName) async =>
      saved.containsKey(fileName) || published.containsKey(fileName);

  @override
  Future<void> remove(String fileName) async {
    saved.remove(fileName);
    published.remove(fileName);
  }

  @override
  Future<PublishedFile> publish(String path, String fileName) async {
    published[fileName] = path;
    return PublishedFile(
      uri: 'content://downloads/$fileName',
      path: 'Download/TeamTalkX/$fileName',
    );
  }

  @override
  Future<bool> open(String uri) async {
    opened.add(uri);
    return canOpen;
  }
}

class FakeAppUpdater implements AppUpdater {
  UpdateDevice deviceInfo = const UpdateDevice(
    packageName: 'org.gozaltech.teamtalkx.dev',
    abis: ['arm64-v8a', 'armeabi-v7a'],
    debuggable: true,
  );
  bool metered = false;
  bool installAllowed = true;
  ApkCheck check = const ApkCheck(
    valid: true,
    packageName: 'org.gozaltech.teamtalkx.dev',
    sameSigner: true,
  );
  final installed = <String>[];
  int settingsOpened = 0;
  final statusController = StreamController<InstallStatus>.broadcast();

  @override
  Future<UpdateDevice> device() async => deviceInfo;
  @override
  Future<bool> isMetered() async => metered;
  @override
  Future<ApkCheck> verify(String path) async => check;
  @override
  Future<bool> canInstall() async => installAllowed;
  @override
  Future<void> openInstallSettings() async => settingsOpened++;
  @override
  Future<void> install(String path) async => installed.add(path);
  @override
  Stream<InstallStatus> get statuses => statusController.stream;

  Future<void> close() => statusController.close();
}

class FakeSoundPackFolder implements SoundPackFolder {
  PickedFolder? toPick;
  List<PackFolderContents> packs = const [];
  bool readable = true;
  final files = <String, Uint8List>{};
  final released = <String>[];

  @override
  Future<PickedFolder?> pick() async => toPick;

  @override
  Future<void> release(String tree) async => released.add(tree);

  @override
  Future<List<PackFolderContents>> list(String tree) async {
    if (!readable) throw const SoundPackFolderUnreadable();
    return packs;
  }

  @override
  Future<Uint8List> read(String uri) async {
    final bytes = files[uri];
    if (!readable || bytes == null) throw const SoundPackFolderUnreadable();
    return bytes;
  }
}

class FakeRecordingFolder implements RecordingFolder {
  PickedFolder? toPick;
  bool writable = true;

  final saved = <String, Uint8List>{};
  final released = <String>[];

  @override
  Future<PickedFolder?> pick() async => toPick;

  @override
  Future<void> release(String tree) async => released.add(tree);

  @override
  Future<String> save(String tree, String path, String name) async {
    if (!writable) throw const RecordingFolderUnwritable();
    final file = File(path);
    saved[name] = file.readAsBytesSync();
    file.deleteSync();
    return name;
  }
}

class FakePermissions implements Permissions {
  bool granted = true;
  final requested = <String>[];

  Future<bool> _ask(String name) async {
    requested.add(name);
    return granted;
  }

  final grantedOnes = <AppPermission>{};

  @override
  Future<bool> isGranted(AppPermission permission) async =>
      grantedOnes.contains(permission);

  @override
  Future<bool> request(AppPermission permission) async {
    requested.add(permission.name);
    if (granted) grantedOnes.add(permission);
    return granted;
  }

  @override
  Future<bool> requestConnect() => _ask('connect');
  @override
  Future<bool> requestPhone() => _ask('phone');
  @override
  Future<bool> requestBluetooth() => _ask('bluetooth');
}

class FakeSoundPlayer implements SoundPlayer {
  final played = <String>[];

  @override
  bool suppressed = false;

  final playingController = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get playing => playingController.stream;

  Future<void> close() => playingController.close();

  final volumes = <int>[];

  @override
  Future<void> play(SoundEvent event) async => played.add(event.name);
  @override
  Future<void> playEventSound(
    SoundEvent event, {
    int volumePercent = 100,
  }) async {
    played.add(event.name);
    volumes.add(volumePercent);
  }

  @override
  Future<void> playAsset(String asset, {int volumePercent = 100}) async {
    played.add(asset);
    volumes.add(volumePercent);
  }

  @override
  Future<void> playFile(String path, {int volumePercent = 100}) async {
    played.add(path);
    volumes.add(volumePercent);
  }

  ({bool voiceCall, int deviceId})? output;
  @override
  void setOutput({required bool voiceCall, int deviceId = 0}) =>
      output = (voiceCall: voiceCall, deviceId: deviceId);

  @override
  void dispose() {}
}

class FakeConnectivity implements Connectivity {
  bool online = true;
  final _changes = StreamController<bool>.broadcast();

  void set({required bool online}) {
    this.online = online;
    _changes.add(online);
  }

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get changes => _changes.stream;

  Future<void> close() => _changes.close();
}

class FakeAudioRouting implements AudioRouting {
  List<AudioOutputDevice> devices = [];

  final changed = StreamController<void>.broadcast();
  final communication = <({bool on, int deviceId})>[];

  @override
  Future<List<AudioOutputDevice>> outputs() async => devices;
  @override
  Stream<void> get outputsChanged => changed.stream;
  @override
  Future<void> setCommunication({required bool on, int deviceId = 0}) async =>
      communication.add((on: on, deviceId: deviceId));

  Future<void> close() => changed.close();
}

class FakePlatform {
  final tts = FakeTts();
  final pmNotifications = FakePmNotifications();
  final foregroundService = FakeForegroundService();
  final haptics = FakeHaptics();
  final hotkeys = FakeHotkeys();
  final mediaKeys = FakeMediaKeys();
  final interruptions = FakeInterruptions();
  final deepLinks = FakeDeepLinks();
  final downloads = FakeDownloads();
  final soundPackFolder = FakeSoundPackFolder();
  final recordingFolder = FakeRecordingFolder();
  final updater = FakeAppUpdater();
  final permissions = FakePermissions();
  final sounds = FakeSoundPlayer();
  final routing = FakeAudioRouting();
  final connectivity = FakeConnectivity();

  int startupDone = 0;

  Future<void> dispose() async {
    await pmNotifications.close();
    await foregroundService.close();
    await hotkeys.close();
    await mediaKeys.close();
    await interruptions.close();
    await sounds.close();
    await deepLinks.close();
    await connectivity.close();
    await updater.close();
    await routing.close();
  }

  List<Override> get overrides => [
    ttsProvider.overrideWithValue(tts),
    reportStartupDoneProvider.overrideWithValue(() async => startupDone++),
    pmNotificationsProvider.overrideWithValue(pmNotifications),
    foregroundServiceProvider.overrideWithValue(foregroundService),
    hapticsProvider.overrideWithValue(haptics),
    hotkeysProvider.overrideWithValue(hotkeys),
    mediaKeysProvider.overrideWithValue(mediaKeys),
    interruptionsProvider.overrideWithValue(interruptions),
    deepLinksProvider.overrideWithValue(deepLinks),
    downloadsProvider.overrideWithValue(downloads),
    soundPackFolderProvider.overrideWithValue(soundPackFolder),
    recordingFolderProvider.overrideWithValue(recordingFolder),
    appUpdaterProvider.overrideWithValue(updater),
    permissionsProvider.overrideWithValue(permissions),
    soundPlayerProvider.overrideWithValue(sounds),
    audioRoutingProvider.overrideWithValue(routing),
    connectivityProvider.overrideWithValue(connectivity),
  ];
}
