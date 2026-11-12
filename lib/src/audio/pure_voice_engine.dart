import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics/log.dart';
import '../domain/capture_settings.dart';
import '../domain/events.dart';
import '../domain/recording.dart';
import '../domain/tt_types.dart' show AudioCodecType;
import '../domain/voice_quality.dart';
import '../protocol/packet.dart';
import '../protocol/protocol_client.dart';
import 'audio_worker.dart';
import 'dsp/silero_voice_detector.dart';

const int _userStateVoice = 1;
const int _userStateMediaFileAudio = 32;

typedef UserGainResolver = double Function(int userId, int streamKind);

typedef MediaStreamStatusHandler =
    void Function(MediaStreamStatus status, {required bool requested});

typedef SileroModelLoader = Future<Uint8List> Function();

Future<Uint8List>? _sileroModel;

Future<Uint8List> _loadSileroModelOnce() =>
    _sileroModel ??= SileroVoiceDetector.loadModelBytes();

class VoiceConnectionException implements Exception {
  const VoiceConnectionException(this.message);
  final String message;

  @override
  String toString() => 'VoiceConnectionException: $message';
}

class PureVoiceEngine {
  PureVoiceEngine(
    this._proto, {
    this.sampleRate = 48000,
    this.channels = 2,
    this.gainResolver = _defaultGainResolver,
    this.onVoiceDetected,
    this.onMediaStatus,
    SileroModelLoader? loadSileroModel,
    this._outputGain = 1,
    this._mediaGain = 1,
    this._normalize = false,
    this._voiceQuality = const VoiceQuality(),
    this._output = const AudioOutput(),
  }) : _loadSileroModel = loadSileroModel ?? _loadSileroModelOnce;

  static double _defaultGainResolver(int userId, int streamKind) => 1.0;

  final ProtocolClient _proto;
  final int sampleRate;
  final int channels;

  final UserGainResolver gainResolver;

  final CaptureVoiceHandler? onVoiceDetected;

  final MediaStreamStatusHandler? onMediaStatus;
  int _mediaStreamId = 0;
  bool _mediaRunning = false;
  bool _mediaStopRequested = false;
  final SileroModelLoader _loadSileroModel;
  CaptureSettings? _captureSettings;

  bool _nativePlayback = false;
  double _outputGain;
  double _mediaGain;
  bool _normalize;
  VoiceQuality _voiceQuality;
  AudioOutput _output;

  ({int audioSource, int sampleRate, int channels})? _captureRequest;
  ({int streamId, bool transmit, bool voiceActive})? _captureState;
  StreamSubscription<TtEvent>? _eventSub;

  AudioWorker? _worker;
  int _extStreamId = 0;
  bool _running = false;

  final Set<(int, int)> _activeStates = {};

  bool get playbackAvailable => _nativePlayback;

  Future<void> start({required String host, required int udpPort}) async {
    if (_running) return;
    _running = true;
    final worker = _worker = await AudioWorker.spawn(
      onTx: (_) {},
      onVoice: onVoiceDetected,
      onActivity: _onActivity,
      onMediaStatus: _onMediaStatus,
      onCaptureError: (error) => _problem(
        VoiceProblem.microphoneFailed,
        'The microphone could not be started ($error)',
      ),
    );
    worker.setOutput(_output);
    _nativePlayback = await worker.startAudio(outputGain: _outputGain);
    worker
      ..setMediaGain(_mediaGain)
      ..setNormalization(enabled: _normalize)
      ..setVoiceQuality(_voiceQuality);
    if (!_nativePlayback) {
      _problem(
        VoiceProblem.playbackFailed,
        'Sound output could not be started',
      );
    }
    if (_captureSettings case final settings?) {
      worker.configureCapture(settings);
    }
    unawaited(_sendSileroModel(worker));
    if (_captureRequest case final c?) {
      worker.startCapture(
        audioSource: c.audioSource,
        sampleRate: c.sampleRate,
        channels: c.channels,
      );
    }
    _sendCaptureState();
    _sendRxConfig();
    _eventSub = _proto.events.listen((event) {
      if (event is UserJoinedEvent && event.user.id == _proto.state.myUserId) {
        _sendCaptureState();
        _sendRxConfig();
        if (_mediaRunning) stopMedia();
      }
    });
    final address =
        _proto.serverAddress ?? (await InternetAddress.lookup(host)).first;
    final error = await worker.startUdp(
      address: address,
      port: udpPort,
      userId: _proto.state.myUserId,
    );
    if (error != null) throw VoiceConnectionException(error);
  }

  void _problem(VoiceProblem problem, String detail) =>
      _proto.applyLocalEvent(VoiceProblemEvent(problem, detail: detail));

  Future<String?> startMedia(
    String path, {
    bool loop = false,
    double gain = 1,
    bool monitor = false,
  }) async {
    final worker = _worker;
    if (worker == null) return 'Voice is not running';
    final channelId = _proto.state.joinedChannelId;
    final wire = _proto.channelCodecs[channelId];
    final opusChannels =
        wire != null && wire.length > 2 && wire[0] == AudioCodecType.opus.value
        ? wire[2].clamp(1, 2)
        : 1;
    _mediaStreamId = _mediaStreamId % 255 + 1;
    final error = await worker.startMedia(
      path: path,
      codec: _channelTxConfig(opusChannels.toInt(), sampleRate),
      streamId: _mediaStreamId,
      userId: _proto.state.myUserId,
      channelId: channelId,
      loop: loop,
      gain: gain,
      monitor: monitor,
    );
    if (error == null) {
      _mediaRunning = true;
      _mediaStopRequested = false;
    }
    return error;
  }

  bool _recording = false;

  bool get recording => _recording;

  Future<String?> startRecording({
    required String directory,
    required RecordingMode mode,
    required RecordingFormat format,
  }) async {
    final worker = _worker;
    if (worker == null) return 'Voice is not running';
    final error = await worker.startRecording(
      directory: directory,
      mode: mode,
      format: format,
    );
    _recording = error == null;
    _recordingStop = null;
    return error;
  }

  Future<void>? _recordingStop;

  Future<void> stopRecording() {
    if (!_recording) return _recordingStop ?? Future.value();
    _recording = false;
    return _recordingStop = _worker?.stopRecording() ?? Future.value();
  }

  void controlMedia({
    bool? paused,
    Duration? seekTo,
    Duration? seekBy,
    bool? loop,
    double? gain,
    bool? monitor,
  }) => _worker?.controlMedia(
    paused: paused,
    seekTo: seekTo,
    seekBy: seekBy,
    loop: loop,
    gain: gain,
    monitor: monitor,
  );

  void stopMedia() {
    if (!_mediaRunning) return;
    _mediaStopRequested = true;
    _worker?.stopMedia();
  }

  void _onMediaStatus(MediaStreamStatus status) {
    if (status.ended) _mediaRunning = false;
    onMediaStatus?.call(status, requested: _mediaStopRequested);
  }

  void userGainChanged(int userId) => _worker?.setUserGain(
    userId,
    voice: gainResolver(userId, packetKindVoice),
    media: gainResolver(userId, packetKindMediaFileAudio),
  );

  void _sendRxConfig() {
    _worker
      ?..setRxCodec(_channelTxConfig(1, sampleRate))
      ..setCryptKey(_proto.voiceCryptKey(_proto.state.joinedChannelId));
  }

  void _onActivity(int userId, int kind, {required bool active}) {
    final bit = kind == packetKindMediaFileAudio
        ? _userStateMediaFileAudio
        : _userStateVoice;
    if (active) {
      _activeStates.add((userId, bit));
    } else {
      _activeStates.remove((userId, bit));
    }
    _setState(userId, bit, active);
  }

  void _setState(int userId, int stateBit, bool on) {
    final user = _proto.state.users[userId];
    if (user == null) return;
    final newState = on
        ? (user.userState | stateBit)
        : (user.userState & ~stateBit);
    if (newState == user.userState) return;
    _proto.applyLocalEvent(
      UserStateChangeEvent(user.copyWith(userState: newState)),
    );
  }

  TxCodecConfig _channelTxConfig(int outChannels, int fallbackRate) {
    final channelId = _proto.state.joinedChannelId;
    return txCodecConfigFromWire(
      _proto.channelCodecs[channelId],
      fallbackRate: fallbackRate,
      outChannels: outChannels,
    );
  }

  Future<void> _sendSileroModel(AudioWorker worker) async {
    try {
      final model = await _loadSileroModel();
      if (identical(_worker, worker)) worker.setSileroModel(model);
    } on Object catch (e, st) {
      _sileroModel = null;
      appLog.w('voice', 'Could not load the Silero model', e, st);
    }
  }

  void configureCapture(CaptureSettings settings) {
    _captureSettings = settings;
    _worker?.configureCapture(settings);
    _sendCaptureState();
  }

  void setOutput(AudioOutput output) {
    _output = output;
    _worker?.setOutput(output);
  }

  void setMediaGain(double gain) {
    _mediaGain = gain;
    _worker?.setMediaGain(gain);
  }

  void setNormalization({required bool enabled}) {
    _normalize = enabled;
    _worker?.setNormalization(enabled: enabled);
  }

  void setVoiceQuality(VoiceQuality quality) {
    _voiceQuality = quality;
    _worker?.setVoiceQuality(quality);
  }

  void setOutputGain(double gain) {
    _outputGain = gain;
    _worker?.setOutputGain(gain);
  }

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
    _worker?.startCapture(
      audioSource: audioSource,
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  void stopCapture() {
    _captureRequest = null;
    _captureState = null;
    _worker?.stopCapture();
  }

  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) {
    _captureState = (
      streamId: streamId,
      transmit: transmit,
      voiceActive: voiceActive,
    );
    _sendCaptureState(flushPreRoll: flushPreRoll);
  }

  void _sendCaptureState({bool flushPreRoll = false}) {
    final worker = _worker;
    final state = _captureState;
    final settings = _captureSettings;
    if (!_running || worker == null || state == null || settings == null) {
      return;
    }
    final stereoOut =
        settings.channels == 2 &&
        settings.outputChannel != 0 &&
        settings.outputChannel != 1;
    worker.setCaptureState(
      streamId: state.streamId,
      userId: _proto.state.myUserId,
      channelId: _proto.state.joinedChannelId,
      transmit: state.transmit,
      flushPreRoll: flushPreRoll,
      voiceActive: state.voiceActive,
      config: _channelTxConfig(stereoOut ? 2 : 1, settings.sampleRate),
    );
  }

  void resetCapture() => _worker?.resetCapture();

  int beginTransmit() {
    _extStreamId = (_extStreamId % 255) + 1;
    return _extStreamId;
  }

  void endTransmit() {
    _worker?.resetTx();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    for (final key in _activeStates.toList()) {
      _setState(key.$1, key.$2, false);
    }
    _activeStates.clear();
    endTransmit();
    await _eventSub?.cancel();
    _eventSub = null;
    await stopRecording();
    await _worker?.shutdown();
    _worker = null;
    _nativePlayback = false;
  }
}
