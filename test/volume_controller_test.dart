import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/output_interruption.dart';
import 'package:teamtalkx/src/app/voice/volume_controller.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/media_stream.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/recording.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/domain/voice_quality.dart';

class _StubClient implements TeamTalkClient {
  _StubClient({this.connected = true, this.inputGain = true})
    : _events = StreamController<TtEvent>.broadcast();

  bool connected;
  bool inputGain;
  final List<int> masterVolumeCalls = [];
  final List<int> micGainCalls = [];
  final List<bool> muteCalls = [];
  final ServerState _state = ServerState();
  final StreamController<TtEvent> _events;

  @override
  bool get isConnected => connected;
  @override
  bool get supportsInputGain => inputGain;

  @override
  Stream<TtEvent> get events => _events.stream;
  @override
  ServerState get state => _state;
  @override
  bool get isVoiceTransmitting => false;
  @override
  bool get isVoiceActivationEnabled => false;
  @override
  int get myUserId => 0;
  @override
  int get rootChannelId => 0;
  @override
  String get serverAccessToken => '';
  @override
  bool get isAdmin => false;
  @override
  int get serverMaxUsers => 100;
  @override
  bool get isStreamingMediaFile => false;
  @override
  int get voiceActivationLevel => 0;
  @override
  int get masterVolume => 0;
  @override
  int get microphoneGain => 0;

  @override
  bool setMasterVolume(int volume) {
    masterVolumeCalls.add(volume);
    return true;
  }

  final mediaVolumeCalls = <int>[];
  final normalizeCalls = <bool>[];
  final qualityCalls = <VoiceQuality>[];
  @override
  void setVoiceQuality(VoiceQuality quality) => qualityCalls.add(quality);
  @override
  void setMediaPlaybackVolume(int percent) => mediaVolumeCalls.add(percent);
  @override
  void setPlaybackNormalization({required bool enabled}) =>
      normalizeCalls.add(enabled);
  @override
  void setAudioOutput({required bool voiceCall, int deviceId = 0}) {}

  @override
  bool setMicrophoneGain(int gain) {
    micGainCalls.add(gain);
    return true;
  }

  @override
  void setSoundOutputMute({required bool muted}) {
    muteCalls.add(muted);
  }

  @override
  int beginAudioInput() => 0;
  final captureStarts = <(int, int, int)>[];
  int captureStops = 0;
  final transmits = <bool>[];
  final captureSettings = <CaptureSettings>[];
  int captureResets = 0;

  @override
  void configureCapture(CaptureSettings settings) =>
      captureSettings.add(settings);
  @override
  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) => captureStarts.add((audioSource, sampleRate, channels));
  @override
  void stopCapture() => captureStops++;
  @override
  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) => transmits.add(transmit);
  @override
  Stream<bool> get captureVoice => const Stream.empty();
  @override
  void resetCapture() => captureResets++;
  @override
  void endAudioInput() {}
  @override
  Future<void> connect(
    String host, {
    int tcpPort = 0,
    int udpPort = 0,
    bool encrypted = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {}
  @override
  void disconnect() {}
  @override
  Future<void> login({
    required String nickname,
    String username = '',
    String password = '',
    String clientName = '',
  }) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<void> joinChannel(int channelId, {String password = ''}) async {}
  @override
  int channelIdFromPath(String path) => 0;
  @override
  String channelPath(int channelId) => '';
  @override
  Future<void> leaveChannel() async {}
  @override
  Future<void> sendChannelMessage(int channelId, String text) async {}
  @override
  Future<void> sendUserMessage(int userId, String text) async {}
  @override
  Future<void> sendBroadcastMessage(String text) async {}
  @override
  Future<void> sendCustomMessage(int userId, String text) async {}
  @override
  Future<void> changeStatus(int statusMode, String statusMessage) async {}
  @override
  Future<void> changeNickname(String nickname) async {}
  @override
  Future<void> subscribe(int userId, int subscriptions) async {}
  @override
  Future<void> unsubscribe(int userId, int subscriptions) async {}
  @override
  void refreshUser(int userId) {}
  @override
  Future<void> listBans({
    int channelId = 0,
    int index = 0,
    int count = 1000,
  }) async {}
  @override
  Future<void> unbanUser(TtBannedUser ban) async {}
  @override
  Future<void> addBan({
    String ipAddress = '',
    String username = '',
    String channelPath = '',
    required int banTypes,
  }) async {}
  @override
  Future<void> listUserAccounts({int index = 0, int count = 1000}) async {}
  @override
  Future<void> createUserAccount(TtUserAccount account) async {}
  @override
  Future<void> deleteUserAccount(String username) async {}
  @override
  TtServerProperties getServerProperties() => const TtServerProperties.empty();
  @override
  Future<void> updateServer(TtServerProperties p) async {}
  @override
  TtChannelConfig getChannelConfig(int channelId) =>
      const TtChannelConfig(name: '', maxUsers: 100);
  @override
  Future<void> saveChannel(
    TtChannelConfig cfg, {
    int? parentId,
    int? channelId,
  }) async {}
  @override
  Future<void> removeChannel(int channelId) async {}
  @override
  Future<void> startStreamingMediaFile(
    String path, {
    required String fileName,
    bool loop = false,
    int volumePercent = 100,
    bool monitor = false,
  }) async {}
  @override
  MediaStreamState? get mediaStream => null;
  @override
  Stream<MediaStreamState?> get mediaStreamChanges => const Stream.empty();
  @override
  void setMediaStreamPaused({required bool paused}) {}
  @override
  void seekMediaStream(Duration position) {}
  @override
  void seekMediaStreamBy(Duration offset) {}
  @override
  void setMediaStreamLoop({required bool loop}) {}
  @override
  void setMediaStreamVolume(int percent) {}
  @override
  void setMediaStreamMonitor({required bool monitor}) {}
  @override
  void stopStreamingMediaFile() {}
  @override
  Future<void> startRecording({
    required String directory,
    required RecordingMode mode,
    required RecordingFormat format,
  }) async {}
  @override
  bool get isRecording => false;
  @override
  Future<void> stopRecording() async {}
  @override
  Future<void> sendFile(int channelId, String localPath) async {}
  @override
  Future<void> recvFile(int channelId, int fileId, String localPath) async {}
  @override
  Future<void> deleteFile(int channelId, int fileId) async {}
  @override
  bool cancelFileTransfer(int transferId) => false;
  @override
  TtFileTransfer? getFileTransferInfo(int transferId) => null;
  @override
  Future<void> kickUser(int userId, {int channelId = 0}) async {}
  @override
  Future<void> banUser(
    int userId, {
    int channelId = 0,
    int banTypes = 0,
  }) async {}
  @override
  Future<void> moveUser(int userId, int channelId) async {}
  @override
  Future<void> channelOperator(
    int userId,
    int channelId, {
    required bool makeOperator,
    String password = '',
  }) async {}
  @override
  Future<TtServerStats> queryServerStats() => throw UnimplementedError();
  @override
  Future<void> setTransmitUsers(
    int channelId, {
    required Set<int> voice,
    required Set<int> mediaFiles,
  }) async {}
  @override
  TtUser? getUser(int userId) => null;
  @override
  int getUserVolume(int userId, {bool media = false}) => 0;
  @override
  bool setUserVolume(int userId, int volume, {bool media = false}) => true;
  @override
  bool isUserMuted(int userId, {bool media = false}) => false;
  @override
  bool setUserMute(int userId, {required bool muted, bool media = false}) =>
      true;
  @override
  bool isChannelOperator(int userId, int channelId) => false;
  @override
  bool setVoiceTransmission({required bool enabled}) => true;
  @override
  bool setVoiceActivation({required bool enabled}) => true;
  @override
  bool setVoiceActivationLevel(int level) => true;
  @override
  void applyLocalEvent(TtEvent event) {}
  @override
  void dispose() {
    unawaited(_events.close());
  }
}

Future<ProviderContainer> _container(
  _StubClient client, {
  bool connected = true,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(shared),
      teamTalkClientProvider.overrideWithValue(client),
      connectionProvider.overrideWith(
        () => _FakeConnection(
          connected ? const LoggedIn(0) : const Disconnected(),
        ),
      ),
    ],
  );
}

class _FakeConnection extends SessionController {
  _FakeConnection(this._initial);
  final ConnectionState _initial;
  @override
  ConnectionState build() => _initial;
}

void main() {
  test('applies current settings to the client on first read', () async {
    final client = _StubClient();
    final container = await _container(client);
    addTearDown(container.dispose);

    container.read(volumeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(client.masterVolumeCalls, isNotEmpty);
    expect(client.micGainCalls, isNotEmpty);
    expect(client.muteCalls, contains(false));
  });

  group('the volume scale', () {
    Future<int> masterFor(Map<String, Object> prefs) async {
      final client = _StubClient();
      final container = await _container(client, prefs: prefs);
      addTearDown(container.dispose);
      container.read(volumeControllerProvider);
      await Future<void>.delayed(Duration.zero);
      return client.masterVolumeCalls.last;
    }

    test('100 % is normal (1000) by default', () async {
      expect(await masterFor(const {}), 1000);
    });

    test('the old SDK-scale master setting converts', () async {
      expect(await masterFor({'master_volume_percent': 50}), 1000);
      expect(await masterFor({'master_volume_percent': 100}), 3000);
      expect(await masterFor({'master_volume_percent': 30}), 350);
      expect(
        await masterFor({
          'master_volume_percent': 50,
          'output_volume_percent': 250,
        }),
        2500,
      );
    });

    test('media volume and normalization reach the client', () async {
      final client = _StubClient();
      final container = await _container(client);
      addTearDown(container.dispose);
      container.read(volumeControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(client.mediaVolumeCalls.last, 100);
      expect(client.normalizeCalls.last, isFalse);

      container.read(settingsProvider.notifier)
        ..setMediaVolumePercent(40)
        ..setNormalizeSpeakers(true);
      await Future<void>.delayed(Duration.zero);

      expect(client.mediaVolumeCalls.last, 40);
      expect(client.normalizeCalls.last, isTrue);
    });
  });

  test('voice quality reaches the client and is remembered', () async {
    final client = _StubClient();
    final container = await _container(client);
    addTearDown(container.dispose);
    container.read(volumeControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(client.qualityCalls.last, const VoiceQuality());

    container.read(settingsProvider.notifier)
      ..setVoiceEnhancement(VoiceEnhancement.better)
      ..setBandwidthExtension(true)
      ..setLossProtection(LossProtection.channelAndDred);
    await Future<void>.delayed(Duration.zero);

    const expected = VoiceQuality(
      enhancement: VoiceEnhancement.better,
      bandwidthExtension: true,
      protection: LossProtection.channelAndDred,
    );
    expect(client.qualityCalls.last, expected);
    final stored = await SharedPreferences.getInstance();
    expect(stored.getString('voice_enhancement'), 'better');
    expect(stored.getBool('bandwidth_extension'), isTrue);
    expect(stored.getString('loss_protection'), 'channelAndDred');

    final reloaded = await _container(
      _StubClient(),
      prefs: {
        'voice_enhancement': 'better',
        'bandwidth_extension': true,
        'loss_protection': 'channelAndDred',
      },
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.read(settingsProvider).voiceQuality, expected);
  });

  test('an interruption ducks or mutes on top of the master', () async {
    final client = _StubClient();
    final container = await _container(client);
    addTearDown(container.dispose);
    container.read(volumeControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final interruption = container.read(outputInterruptionProvider.notifier);

    interruption.set(InterruptionSource.call, OutputEffect.duck);
    await Future<void>.delayed(Duration.zero);
    expect(client.masterVolumeCalls.last, (1000 * duckGain).round());
    expect(client.muteCalls.last, isFalse);

    interruption.set(InterruptionSource.call, OutputEffect.mute);
    await Future<void>.delayed(Duration.zero);
    expect(client.muteCalls.last, isTrue);

    interruption.set(InterruptionSource.call, null);
    await Future<void>.delayed(Duration.zero);
    expect(client.masterVolumeCalls.last, 1000);
    expect(client.muteCalls.last, isFalse);
  });

  test('re-applies when settings change', () async {
    final client = _StubClient();
    final container = await _container(client);
    addTearDown(container.dispose);

    container.read(volumeControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final before = client.masterVolumeCalls.length;

    container.read(settingsProvider.notifier).setMasterVolumePercent(80);
    await Future<void>.delayed(Duration.zero);

    expect(client.masterVolumeCalls.length, greaterThan(before));
  });

  test(
    'does not call setMicrophoneGain when supportsInputGain is false',
    () async {
      final client = _StubClient(inputGain: false);
      final container = await _container(client);
      addTearDown(container.dispose);

      container.read(volumeControllerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(client.micGainCalls, isEmpty);
      expect(client.masterVolumeCalls, isNotEmpty);
    },
  );

  test('suppresses calls while disconnected', () async {
    final client = _StubClient(connected: false);
    final container = await _container(client, connected: false);
    addTearDown(container.dispose);

    container.read(volumeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(client.masterVolumeCalls, isEmpty);
  });
}
