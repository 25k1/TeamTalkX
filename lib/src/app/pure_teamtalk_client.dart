import 'dart:async';
import 'dart:io';

import '../audio/audio_worker.dart' show AudioOutput;
import '../audio/media_streamer.dart' show MediaStreamStatus;
import '../audio/pure_voice_engine.dart';
import '../diagnostics/log.dart';
import '../domain/capture_settings.dart';
import '../domain/certificate.dart';
import '../domain/events.dart';
import '../domain/failure.dart';
import '../domain/media_stream.dart';
import '../domain/models.dart';
import '../domain/recording.dart';
import '../domain/server_state.dart';
import '../domain/sound_level.dart';
import '../domain/teamtalk_client.dart';
import '../domain/tt_types.dart' show BanTypes, UserRights;
import '../domain/voice_quality.dart';
import '../protocol/packet.dart';
import '../protocol/protocol_client.dart';
import '../protocol/tt_connection.dart';
import 'app_info.dart';

class PureTeamTalkClient implements TeamTalkClient {
  PureTeamTalkClient({
    this.appVersion = unknownAppVersion,
    CertificateTrust trust = const AuthorityTrustOnly(),
  }) : _proto = ProtocolClient(trust: trust);

  final ProtocolClient _proto;

  final String appVersion;

  PureVoiceEngine? _voice;
  String _host = '';
  int _udpPortHint = 0;
  bool _txEnabled = false;
  bool _tornDown = false;
  Future<void>? _teardownFuture;

  final _captureVoice = StreamController<bool>.broadcast();
  CaptureSettings? _captureSettings;
  ({int audioSource, int sampleRate, int channels})? _captureRequest;
  ({int streamId, bool transmit, bool voiceActive})? _captureTransmit;
  double _outputGain = 1.0;

  int _session = 0;

  int _masterVolume = 0;
  int _microphoneGain = 0;
  int _voiceActivationLevel = 0;

  final Map<int, _UserAudioState> _userAudio = {};

  double _savedOutputGain = 1.0;
  bool _outputMuted = false;

  @override
  ServerState get state => _proto.state;

  @override
  Stream<TtEvent> get events => _proto.events;

  @override
  bool get isConnected => _proto.isConnected;

  @override
  bool get isVoiceTransmitting => _txEnabled;

  @override
  bool get isVoiceActivationEnabled => false;

  @override
  int get myUserId => _proto.state.myUserId;

  @override
  int get rootChannelId => _proto.state.rootChannel?.id ?? 0;

  @override
  String get serverAccessToken => '';

  @override
  bool get isAdmin => (_proto.myUserType & 2) != 0;

  @override
  int get serverMaxUsers => _proto.serverProperties?.maxUsers ?? 128;

  @override
  bool get isStreamingMediaFile => _media != null;

  MediaStreamState? _media;
  final _mediaChanges = StreamController<MediaStreamState?>.broadcast();

  @override
  MediaStreamState? get mediaStream => _media;

  @override
  Stream<MediaStreamState?> get mediaStreamChanges => _mediaChanges.stream;

  void _setMedia(MediaStreamState? media) {
    _media = media;
    if (!_mediaChanges.isClosed) _mediaChanges.add(media);
  }

  void _onMediaStatus(MediaStreamStatus status, {required bool requested}) {
    final media = _media;
    if (media == null) return;
    if (status.ended) {
      _setMedia(null);
      if (!requested) {
        _proto.applyLocalEvent(
          MediaStreamEndedEvent(media.fileName, failed: status.error != null),
        );
      }
      return;
    }
    _setMedia(
      media.copyWith(
        position: status.position,
        duration: status.duration,
        paused: status.paused,
      ),
    );
  }

  @override
  int get voiceActivationLevel => _voiceActivationLevel;

  @override
  int get masterVolume => _masterVolume;

  @override
  int get microphoneGain => _microphoneGain;

  @override
  Future<void> connect(
    String host, {
    int tcpPort = 10333,
    int udpPort = 10333,
    bool encrypted = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await _teardownFuture;
    _teardownFuture = null;
    _host = host;
    _udpPortHint = udpPort;
    try {
      await _proto
          .connect(host: host, tcpPort: tcpPort, encrypted: encrypted)
          .timeout(timeout);
    } on TimeoutException {
      throw const ConnectionTimedOut();
    } on TlsException catch (e) {
      appLog.w('connection', 'TLS handshake with $host failed', e);
      throw const SecureConnectionFailed();
    } on SocketException catch (e) {
      appLog.w('connection', 'Could not reach $host:$tcpPort', e);
      throw const ServerUnreachable();
    }
  }

  @override
  Future<void> login({
    required String nickname,
    String username = '',
    String password = '',
    String clientName = appClientName,
  }) async {
    final session = _session;
    await _proto.login(
      nickname: nickname,
      username: username,
      password: password,
      clientName: clientName,
      version: appVersion,
    );
    if (session != _session) throw const ConnectionCancelled();
    _setMedia(null);
    await _stopVoice(_voice);
    final udpPort = _proto.udpPort != 0 ? _proto.udpPort : _udpPortHint;
    final engine = PureVoiceEngine(
      _proto,
      gainResolver: resolveUserGain,
      onVoiceDetected: _captureVoice.add,
      onMediaStatus: _onMediaStatus,
      outputGain: _outputGain,
      mediaGain: _mediaPlaybackGain,
      normalize: _normalize,
      voiceQuality: _voiceQuality,
      output: _audioOutput,
    );
    if (_captureSettings case final settings?) {
      engine.configureCapture(settings);
    }
    if (_captureRequest case final c?) {
      engine.startCapture(
        audioSource: c.audioSource,
        sampleRate: c.sampleRate,
        channels: c.channels,
      );
    }
    if (_captureTransmit case final t?) {
      engine.setCaptureTransmit(
        t.streamId,
        transmit: t.transmit,
        voiceActive: t.voiceActive,
      );
    }
    _voice = engine;
    try {
      await engine.start(host: _host, udpPort: udpPort);
    } on VoiceConnectionException catch (e) {
      appLog.e('voice', 'No voice connection (UDP $udpPort)', e);
      _proto.applyLocalEvent(
        VoiceProblemEvent(VoiceProblem.serverUnreachable, detail: e.message),
      );
    } on Object catch (e, st) {
      appLog.e('voice', 'Voice engine failed to start (UDP $udpPort)', e, st);
      _proto.applyLocalEvent(
        VoiceProblemEvent(VoiceProblem.startFailed, detail: '$e'),
      );
    }
    for (final userId in _userAudio.keys) {
      engine.userGainChanged(userId);
    }
    if (session != _session) {
      if (identical(_voice, engine)) _voice = null;
      await _stopVoice(engine);
      throw const ConnectionCancelled();
    }
  }

  @override
  Future<void> logout() => _proto.disconnect();

  @override
  void disconnect() {
    _session++;
    _teardownFuture = _teardown();
  }

  Future<void> _teardown() async {
    _txEnabled = false;
    _setMedia(null);
    final voice = _voice;
    _voice = null;
    await _stopVoice(voice);
    await _proto.disconnect();
  }

  Future<void>? _stoppingVoice;

  Future<void> _stopVoice(PureVoiceEngine? voice) async {
    if (voice == null) return;
    final stopping = _stoppingVoice = voice.stop();
    try {
      await stopping;
    } finally {
      if (identical(_stoppingVoice, stopping)) _stoppingVoice = null;
    }
  }

  @override
  Future<void> joinChannel(int channelId, {String password = ''}) =>
      _proto.joinChannel(channelId, password: password);

  @override
  Future<void> leaveChannel() => _proto.leaveChannel();

  @override
  int channelIdFromPath(String path) {
    final root = _proto.state.rootChannel;
    if (root == null) return 0;
    var current = root.id;
    for (final name in path.split('/').where((p) => p.isNotEmpty)) {
      final children = _proto.state.childrenOf(current);
      TtChannel? match;
      for (final c in children) {
        if (c.name == name) {
          match = c;
          break;
        }
      }
      if (match == null) return 0;
      current = match.id;
    }
    return current;
  }

  @override
  String channelPath(int channelId) {
    final channels = _proto.state.channels;
    final root = _proto.state.rootChannel;
    if (root == null) return '';
    if (channelId == root.id) return '/';
    final names = <String>[];
    var id = channelId;
    while (true) {
      final c = channels[id];
      if (c == null) return '';
      if (c.id == root.id) break;
      names.add(c.name);
      if (c.parentId == 0 || c.parentId == c.id) break;
      id = c.parentId;
    }
    return '/${names.reversed.join('/')}/';
  }

  @override
  Future<void> sendChannelMessage(int channelId, String text) =>
      _proto.sendChannelMessage(channelId, text);

  @override
  Future<void> sendUserMessage(int userId, String text) =>
      _proto.sendUserMessage(userId, text);

  @override
  Future<void> sendBroadcastMessage(String text) =>
      _proto.sendBroadcastMessage(text);

  @override
  Future<void> sendCustomMessage(int userId, String text) =>
      _proto.sendCustomMessage(userId, text);

  @override
  Future<void> changeStatus(int statusMode, String statusMessage) =>
      _proto.changeStatus(statusMode, statusMessage);

  @override
  Future<void> changeNickname(String nickname) =>
      _proto.changeNickname(nickname);

  @override
  Future<void> subscribe(int userId, int subscriptions) =>
      _proto.subscribe(userId, subscriptions);

  @override
  Future<void> unsubscribe(int userId, int subscriptions) =>
      _proto.unsubscribe(userId, subscriptions);

  @override
  void refreshUser(int userId) {}

  @override
  bool setVoiceTransmission({required bool enabled}) {
    _txEnabled = enabled;
    final current = _captureTransmit;
    if (!enabled && current != null && current.transmit) {
      setCaptureTransmit(current.streamId, transmit: false);
    }
    return _voice != null;
  }

  @override
  bool setVoiceActivation({required bool enabled}) => false;

  @override
  bool setVoiceActivationLevel(int level) {
    _voiceActivationLevel = level;
    return true;
  }

  @override
  void applyLocalEvent(TtEvent event) {
    _proto.applyLocalEvent(event);
  }

  @override
  bool setMasterVolume(int volume) {
    _masterVolume = volume;
    final gain = volume / 1000.0;
    if (_outputMuted) {
      _savedOutputGain = gain;
    } else {
      _setOutputGain(gain);
    }
    return true;
  }

  @override
  bool setMicrophoneGain(int gain) {
    _microphoneGain = gain;
    return true;
  }

  @override
  bool get supportsInputGain => false;

  @override
  TtUser? getUser(int userId) => _proto.state.users[userId];

  @override
  int getUserVolume(int userId, {bool media = false}) {
    final s = _userAudio[userId];
    final v = s == null ? null : (media ? s.media : s.voice);
    return v ?? volumeNormal;
  }

  @override
  bool setUserVolume(int userId, int volume, {bool media = false}) {
    final s = _userAudio.putIfAbsent(userId, _UserAudioState.new);
    if (media) {
      s.media = volume;
    } else {
      s.voice = volume;
    }
    _voice?.userGainChanged(userId);
    return true;
  }

  @override
  bool isUserMuted(int userId, {bool media = false}) {
    final s = _userAudio[userId];
    if (s == null) return false;
    return media ? s.mediaMuted : s.voiceMuted;
  }

  @override
  bool setUserMute(int userId, {required bool muted, bool media = false}) {
    final s = _userAudio.putIfAbsent(userId, _UserAudioState.new);
    if (media) {
      s.mediaMuted = muted;
    } else {
      s.voiceMuted = muted;
    }
    _voice?.userGainChanged(userId);
    return true;
  }

  double resolveUserGain(int userId, int streamKind) {
    final s = _userAudio[userId];
    if (s == null) return 1.0;
    final isMedia = streamKind == packetKindMediaFileAudio;
    if (isMedia ? s.mediaMuted : s.voiceMuted) return 0.0;
    final v = isMedia ? s.media : s.voice;
    if (v == null) return 1.0;
    return gainFromVolume(v);
  }

  double _mediaPlaybackGain = 1;
  bool _normalize = false;
  VoiceQuality _voiceQuality = const VoiceQuality();
  AudioOutput _audioOutput = const AudioOutput();

  @override
  void setAudioOutput({required bool voiceCall, int deviceId = 0}) {
    _audioOutput = AudioOutput(voiceCall: voiceCall, deviceId: deviceId);
    _voice?.setOutput(_audioOutput);
  }

  @override
  void setMediaPlaybackVolume(int percent) {
    _mediaPlaybackGain = percent.clamp(0, volumePercentMax) / 100;
    _voice?.setMediaGain(_mediaPlaybackGain);
  }

  @override
  void setPlaybackNormalization({required bool enabled}) {
    _normalize = enabled;
    _voice?.setNormalization(enabled: enabled);
  }

  @override
  void setVoiceQuality(VoiceQuality quality) {
    _voiceQuality = quality;
    _voice?.setVoiceQuality(quality);
  }

  @override
  bool isChannelOperator(int userId, int channelId) =>
      _proto.state.channels[channelId]?.operators.contains(userId) ?? false;

  @override
  int beginAudioInput() => _voice?.beginTransmit() ?? 0;

  @override
  void configureCapture(CaptureSettings settings) {
    _captureSettings = settings;
    _voice?.configureCapture(settings);
  }

  @override
  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) {
    _captureRequest = (
      audioSource: audioSource,
      sampleRate: sampleRate,
      channels: channels,
    );
    _voice?.startCapture(
      audioSource: audioSource,
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  @override
  void stopCapture() {
    _captureRequest = null;
    _captureTransmit = null;
    _voice?.stopCapture();
  }

  @override
  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) {
    _captureTransmit = (
      streamId: streamId,
      transmit: transmit,
      voiceActive: voiceActive,
    );
    _voice?.setCaptureTransmit(
      streamId,
      transmit: transmit,
      flushPreRoll: flushPreRoll,
      voiceActive: voiceActive,
    );
  }

  void _setOutputGain(double gain) {
    _outputGain = gain;
    _voice?.setOutputGain(gain);
  }

  @override
  Stream<bool> get captureVoice => _captureVoice.stream;

  @override
  void resetCapture() => _voice?.resetCapture();

  @override
  void endAudioInput() => _voice?.endTransmit();

  @override
  void setSoundOutputMute({required bool muted}) {
    if (muted == _outputMuted) return;
    _outputMuted = muted;
    if (muted) {
      _savedOutputGain = _masterVolume / 1000.0;
      _setOutputGain(0.0);
    } else {
      _setOutputGain(_savedOutputGain);
    }
  }

  @override
  Future<void> listBans({int channelId = 0, int index = 0, int count = 1000}) =>
      _proto.listBans(channelId: channelId, index: index, count: count);

  @override
  Future<void> unbanUser(TtBannedUser ban) => _proto.unbanUser(ban);

  @override
  Future<void> addBan({
    String ipAddress = '',
    String username = '',
    String channelPath = '',
    required int banTypes,
  }) => _proto.addBan(
    ipAddress: ipAddress,
    username: username,
    channelPath: channelPath,
    banTypes: banTypes,
  );

  @override
  Future<void> listUserAccounts({int index = 0, int count = 1000}) =>
      _proto.listUserAccounts(index: index, count: count);

  @override
  Future<void> createUserAccount(TtUserAccount account) =>
      _proto.createUserAccount(account);

  @override
  Future<void> deleteUserAccount(String username) =>
      _proto.deleteUserAccount(username);

  @override
  TtServerProperties getServerProperties() =>
      _proto.serverProperties ?? const TtServerProperties.empty();

  @override
  Future<void> updateServer(TtServerProperties p) => _proto.updateServer(p);

  @override
  TtChannelConfig getChannelConfig(int channelId) =>
      _proto.channelConfig(channelId) ??
      TtChannelConfig(name: '', maxUsers: serverMaxUsers);

  @override
  Future<void> saveChannel(
    TtChannelConfig cfg, {
    int? parentId,
    int? channelId,
  }) => _proto.saveChannel(cfg, parentId: parentId, channelId: channelId);

  @override
  Future<void> removeChannel(int channelId) => _proto.removeChannel(channelId);

  @override
  Future<void> startStreamingMediaFile(
    String path, {
    required String fileName,
    bool loop = false,
    int volumePercent = 100,
    bool monitor = false,
  }) async {
    final voice = _voice;
    if (voice == null || !_proto.isConnected) throw const NotConnected();
    if (_proto.state.joinedChannelId <= 0) {
      throw const ServerRejected(ServerError.notInChannel);
    }
    if (!_proto.state.hasRight(UserRights.transmitMediaFileAudio)) {
      throw const ServerRejected(ServerError.notAuthorized);
    }
    _setMedia(null);
    final error = await voice.startMedia(
      path,
      loop: loop,
      gain: volumePercent / 100,
      monitor: monitor,
    );
    if (error != null) {
      appLog.w('media', 'Could not stream $fileName: $error');
      throw const MediaFileUnplayable();
    }
    _setMedia(
      MediaStreamState(
        fileName: fileName,
        loop: loop,
        volumePercent: volumePercent,
        monitor: monitor,
      ),
    );
  }

  @override
  Future<void> startRecording({
    required String directory,
    required RecordingMode mode,
    required RecordingFormat format,
  }) async {
    final voice = _voice;
    if (voice == null || !_proto.isConnected) throw const NotConnected();
    final error = await voice.startRecording(
      directory: directory,
      mode: mode,
      format: format,
    );
    if (error != null) {
      appLog.w('recording', 'Could not start recording: $error');
      throw const RecordingFailed();
    }
  }

  @override
  bool get isRecording => _voice?.recording ?? false;

  @override
  Future<void> stopRecording() async {
    await _voice?.stopRecording();
    await _stoppingVoice;
  }

  @override
  void setMediaStreamPaused({required bool paused}) {
    _voice?.controlMedia(paused: paused);
    if (_media case final m?) _setMedia(m.copyWith(paused: paused));
  }

  @override
  void seekMediaStream(Duration position) =>
      _voice?.controlMedia(seekTo: position);

  @override
  void seekMediaStreamBy(Duration offset) =>
      _voice?.controlMedia(seekBy: offset);

  @override
  void setMediaStreamLoop({required bool loop}) {
    _voice?.controlMedia(loop: loop);
    if (_media case final m?) _setMedia(m.copyWith(loop: loop));
  }

  @override
  void setMediaStreamVolume(int percent) {
    final p = percent.clamp(0, 200);
    _voice?.controlMedia(gain: p / 100);
    if (_media case final m?) _setMedia(m.copyWith(volumePercent: p));
  }

  @override
  void setMediaStreamMonitor({required bool monitor}) {
    _voice?.controlMedia(monitor: monitor);
    if (_media case final m?) _setMedia(m.copyWith(monitor: monitor));
  }

  @override
  void stopStreamingMediaFile() {
    _voice?.stopMedia();
    _setMedia(null);
  }

  @override
  Future<void> sendFile(int channelId, String localPath) =>
      _proto.sendFile(channelId, localPath);

  TtRemoteFile _fileInChannel(int channelId, int fileId) => _proto.state
      .filesInChannel(channelId)
      .firstWhere(
        (f) => f.fileId == fileId,
        orElse: () =>
            throw StateError('File $fileId not found in channel $channelId'),
      );

  @override
  Future<void> recvFile(int channelId, int fileId, String localPath) {
    final file = _fileInChannel(channelId, fileId);
    return _proto.recvFile(
      channelId,
      fileId,
      localPath,
      file.fileName,
      file.fileSize,
    );
  }

  @override
  Future<void> deleteFile(int channelId, int fileId) {
    final file = _fileInChannel(channelId, fileId);
    return _proto.deleteFile(channelId, file.fileName);
  }

  @override
  bool cancelFileTransfer(int transferId) =>
      _proto.cancelFileTransfer(transferId);

  @override
  TtFileTransfer? getFileTransferInfo(int transferId) =>
      _proto.fileTransferInfo(transferId);

  @override
  Future<void> kickUser(int userId, {int channelId = 0}) =>
      _proto.kickUser(userId, channelId: channelId);

  @override
  Future<void> banUser(
    int userId, {
    int channelId = 0,
    int banTypes = BanTypes.ipAddress,
  }) => _proto.banUser(userId, channelId: channelId, banTypes: banTypes);

  @override
  Future<void> moveUser(int userId, int channelId) =>
      _proto.moveUser(userId, channelId);

  @override
  Future<void> channelOperator(
    int userId,
    int channelId, {
    required bool makeOperator,
    String password = '',
  }) => _proto.channelOperator(
    userId,
    channelId,
    makeOperator: makeOperator,
    password: password,
  );

  @override
  Future<TtServerStats> queryServerStats() => _proto.queryServerStats();

  @override
  Future<void> setTransmitUsers(
    int channelId, {
    required Set<int> voice,
    required Set<int> mediaFiles,
  }) =>
      _proto.setTransmitUsers(channelId, voice: voice, mediaFiles: mediaFiles);

  @override
  void dispose() {
    if (_tornDown) return;
    _tornDown = true;
    unawaited(_teardown().then((_) => _proto.dispose()));
    unawaited(_captureVoice.close());
  }
}

class _UserAudioState {
  _UserAudioState();

  int? voice;
  int? media;
  bool voiceMuted = false;
  bool mediaMuted = false;
}
