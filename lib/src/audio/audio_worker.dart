import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../diagnostics/log.dart';
import '../domain/capture_settings.dart';
import '../domain/recording.dart';
import '../domain/tt_types.dart' show AudioCodecType;
import '../domain/voice_quality.dart';
import '../protocol/packet.dart';
import '../protocol/voice_crypt.dart';
import 'audio_packetizer.dart';
import 'capture_pipeline.dart';
import 'codec_config.dart';
import 'dsp/pcm_resampler.dart';
import 'dsp/playback_normalizer.dart';
import 'dsp/time_stretch.dart';
import 'media_source.dart';
import 'media_streamer.dart';
import 'mic_test.dart';
import 'native_engine.dart';
import 'output_idle.dart';
import 'playout_buffer.dart';
import 'recorder.dart';
import 'recording_writers.dart';
import 'sound_effects.dart';
import 'udp_connection.dart';
import 'voice_decoder.dart';

export 'codec_config.dart';
export 'media_streamer.dart' show MediaStreamStatus;
export 'mic_test.dart' show MicTestPhase;

part 'worker/capture_job.dart';
part 'worker/media_job.dart';
part 'worker/messages.dart';
part 'worker/mic_test_job.dart';
part 'worker/network_job.dart';
part 'worker/output_job.dart';
part 'worker/receive_job.dart';
part 'worker/recording_job.dart';
part 'worker/worker.dart';

class TxPackets {
  const TxPackets(this.packets);

  final List<Uint8List> packets;
}

class RxDecoded {
  const RxDecoded(this.key, this.pcm);

  final int key;

  final Int16List pcm;
}

typedef TxPacketsHandler = void Function(TxPackets packets);

typedef RxDecodedHandler = void Function(RxDecoded decoded);

typedef CaptureVoiceHandler = void Function(bool voice);

typedef CaptureErrorHandler = void Function(int error);

typedef MicTestHandler = void Function(MicTestPhase phase);

typedef MediaStatusHandler = void Function(MediaStreamStatus status);

typedef StreamActivityHandler =
    void Function(int userId, int kind, {required bool active});

class PlayoutStats {
  const PlayoutStats({
    required this.key,
    required this.targetMs,
    required this.jitterMs,
    required this.bufferedMs,
    required this.speed,
    required this.concealed,
    required this.late,
    required this.catchUpMs,
    required this.slowDownMs,
    this.recovered = 0,
  });

  final int key;
  final double targetMs;
  final double jitterMs;

  final double bufferedMs;
  final double speed;
  final int concealed;
  final int late;
  final double catchUpMs;
  final double slowDownMs;
  final int recovered;

  @override
  String toString() =>
      'key $key: target ${targetMs.round()} ms, jitter '
      '${jitterMs.toStringAsFixed(1)} ms, buffered ${bufferedMs.round()} ms, '
      'speed $speed, concealed $concealed, recovered $recovered, '
      'late $late, faster '
      '${catchUpMs.round()} ms, slower ${slowDownMs.round()} ms';
}

class AudioOutput {
  const AudioOutput({this.voiceCall = false, this.deviceId = 0});

  final bool voiceCall;

  final int deviceId;

  @override
  bool operator ==(Object other) =>
      other is AudioOutput &&
      other.voiceCall == voiceCall &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(voiceCall, deviceId);
}

class AudioWorker {
  static Future<AudioWorker> spawn({
    required TxPacketsHandler onTx,
    RxDecodedHandler? onRx,
    CaptureVoiceHandler? onVoice,
    StreamActivityHandler? onActivity,
    CaptureErrorHandler? onCaptureError,
    MediaStatusHandler? onMediaStatus,
    MicTestHandler? onMicTest,
  }) async {
    final responses = ReceivePort();
    final status = _StatusSlot();
    final isolate = await Isolate.spawn(_workerMain, responses.sendPort);
    final completer = Completer<SendPort>();
    final sub = responses.listen((Object? msg) {
      if (msg is SendPort && !completer.isCompleted) {
        completer.complete(msg);
        return;
      }
      if (msg is TxPackets) {
        onTx(msg);
      } else if (msg is RxDecoded) {
        onRx?.call(msg);
      } else if (msg is _CaptureVoiceMsg) {
        onVoice?.call(msg.voice);
      } else if (msg is MicTestPhase) {
        onMicTest?.call(msg);
      } else if (msg is MediaStreamStatus) {
        onMediaStatus?.call(msg);
      } else if (msg is _MediaStartedMsg) {
        final pending = status.media;
        if (pending != null && !pending.isCompleted) pending.complete(msg);
      } else if (msg is _CaptureErrorMsg) {
        onCaptureError?.call(msg.error);
      } else if (msg is _ActivityMsg) {
        onActivity?.call(msg.userId, msg.kind, active: msg.active);
      } else if (msg is _UdpStatusMsg) {
        final pending = status.udp;
        if (pending != null && !pending.isCompleted) pending.complete(msg);
      } else if (msg is _AudioStatusMsg) {
        final pending = status.pending;
        if (pending != null && !pending.isCompleted) pending.complete(msg);
      } else if (msg is _StatsReplyMsg) {
        final pending = status.stats;
        if (pending != null && !pending.isCompleted) pending.complete(msg);
      } else if (msg is _RecordingReplyMsg) {
        final pending = status.recording;
        if (pending != null && !pending.isCompleted) pending.complete(msg);
      } else if (msg is _WorkerLogMsg) {
        appLog.log(msg.level, 'audio', msg.message, msg.error);
      }
    });
    final SendPort commands;
    try {
      commands = await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      await sub.cancel();
      responses.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
    return AudioWorker._(isolate, commands, responses, sub, status);
  }

  AudioWorker._(
    this._isolate,
    this._commands,
    this._responses,
    this._sub,
    this._status,
  );

  final Isolate _isolate;
  final SendPort _commands;
  final _StatusSlot _status;
  final ReceivePort _responses;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  Future<bool> startAudio({double outputGain = 1}) async {
    if (_disposed) return false;
    final status = _status.pending = Completer<_AudioStatusMsg>();
    _commands.send(_StartAudioMsg(outputGain: outputGain));
    try {
      final result = await status.future.timeout(const Duration(seconds: 5));
      if (!result.playback) {
        appLog.w('audio', 'Native playback unavailable (${result.error})');
      }
      return result.playback;
    } on TimeoutException {
      appLog.w('audio', 'The audio worker did not report playback status');
      return false;
    } finally {
      if (identical(_status.pending, status)) _status.pending = null;
    }
  }

  Future<String?> startUdp({
    required InternetAddress address,
    required int port,
    required int userId,
  }) async {
    if (_disposed) return 'The audio worker is closed';
    final reply = _status.udp = Completer<_UdpStatusMsg>();
    _commands.send(_StartUdpMsg(address.address, port, userId));
    try {
      return (await reply.future.timeout(const Duration(seconds: 10))).error;
    } on TimeoutException {
      return 'The audio worker did not answer';
    } finally {
      if (identical(_status.udp, reply)) _status.udp = null;
    }
  }

  Future<String?> startMedia({
    required String path,
    required TxCodecConfig codec,
    required int streamId,
    required int userId,
    required int channelId,
    bool loop = false,
    double gain = 1,
    bool monitor = false,
    double monitorGain = 1,
  }) async {
    if (_disposed) return 'The audio worker is closed';
    final reply = _status.media = Completer<_MediaStartedMsg>();
    _commands.send(
      _StartMediaMsg(
        path: path,
        codec: codec,
        streamId: streamId,
        userId: userId,
        channelId: channelId,
        loop: loop,
        gain: gain,
        monitor: monitor,
        monitorGain: monitorGain,
      ),
    );
    try {
      return (await reply.future.timeout(const Duration(seconds: 10))).error;
    } on TimeoutException {
      return 'The audio worker did not answer';
    } finally {
      if (identical(_status.media, reply)) _status.media = null;
    }
  }

  void controlMedia({
    bool? paused,
    Duration? seekTo,
    Duration? seekBy,
    bool? loop,
    double? gain,
    bool? monitor,
    double? monitorGain,
  }) {
    if (_disposed) return;
    _commands.send(
      _MediaControlMsg(
        paused: paused,
        seekTo: seekTo,
        seekBy: seekBy,
        loop: loop,
        gain: gain,
        monitor: monitor,
        monitorGain: monitorGain,
      ),
    );
  }

  void startMicTest({
    required bool live,
    Duration record = const Duration(seconds: 5),
  }) {
    if (_disposed) return;
    _commands.send(_MicTestMsg(live: live, recordMs: record.inMilliseconds));
  }

  void stopMicTest() {
    if (_disposed) return;
    _commands.send(const _StopMicTestMsg());
  }

  void stopMedia() {
    if (_disposed) return;
    _commands.send(const _MediaControlMsg(stop: true));
  }

  Future<String?> startRecording({
    required String directory,
    required RecordingMode mode,
    required RecordingFormat format,
  }) async {
    if (_disposed) return 'The audio worker is closed';
    final reply = _status.recording = Completer<_RecordingReplyMsg>();
    _commands.send(_StartRecordingMsg(directory, mode, format));
    try {
      return (await reply.future.timeout(const Duration(seconds: 30))).error;
    } on TimeoutException {
      return 'The audio worker did not answer';
    } finally {
      if (identical(_status.recording, reply)) _status.recording = null;
    }
  }

  Future<void> stopRecording() async {
    if (_disposed) return;
    final reply = _status.recording = Completer<_RecordingReplyMsg>();
    _commands.send(const _StopRecordingMsg());
    try {
      await reply.future.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      appLog.w('audio', 'The recording did not finish in time');
    } finally {
      if (identical(_status.recording, reply)) _status.recording = null;
    }
  }

  void setUserGain(int userId, {required double voice, required double media}) {
    if (_disposed) return;
    _commands.send(_UserGainMsg(userId, voice, media));
  }

  void setCryptKey(Uint8List? key) {
    if (_disposed) return;
    _commands.send(_CryptKeyMsg(key));
  }

  void setRxCodec(TxCodecConfig codec) {
    if (_disposed) return;
    _commands.send(_RxConfigMsg(codec));
  }

  Future<EngineStats?> engineStats() async => (await _stats())?.stats;

  Future<List<PlayoutStats>> playoutStats() async =>
      (await _stats())?.playout ?? const [];

  Future<_StatsReplyMsg?> _stats() async {
    if (_disposed) return null;
    final reply = _status.stats ??= Completer<_StatsReplyMsg>();
    _commands.send(const _StatsRequestMsg());
    try {
      return await reply.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return null;
    } finally {
      if (identical(_status.stats, reply)) _status.stats = null;
    }
  }

  void setOutputGain(double gain) {
    if (_disposed) return;
    _commands.send(_OutputGainMsg(gain));
  }

  void setOutput(AudioOutput output) {
    if (_disposed) return;
    _commands.send(output);
  }

  void setMediaGain(double gain) {
    if (_disposed) return;
    _commands.send(_MediaGainMsg(gain));
  }

  void setVoiceQuality(VoiceQuality quality) {
    if (_disposed) return;
    _commands.send(quality);
  }

  void setNormalization({required bool enabled}) {
    if (_disposed) return;
    _commands.send(_NormalizeMsg(enabled: enabled));
  }

  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) {
    if (_disposed) return;
    _commands.send(
      _StartCaptureMsg(
        audioSource: audioSource,
        sampleRate: sampleRate,
        channels: channels,
      ),
    );
  }

  void stopCapture() {
    if (_disposed) return;
    _commands.send(const _StopCaptureMsg());
  }

  void setCaptureState({
    required int streamId,
    required int userId,
    required int channelId,
    required bool transmit,
    required TxCodecConfig config,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) {
    if (_disposed) return;
    _commands.send(
      _CaptureStateMsg(
        streamId: streamId,
        userId: userId,
        channelId: channelId,
        transmit: transmit,
        flushPreRoll: flushPreRoll,
        voiceActive: voiceActive,
        config: config,
      ),
    );
  }

  @visibleForTesting
  void injectCapture(Int16List pcm) {
    if (_disposed) return;
    _commands.send(_InjectCaptureMsg(pcm));
  }

  void configureCapture(CaptureSettings settings) {
    if (_disposed) return;
    _commands.send(_CaptureSettingsMsg(settings));
  }

  void setSileroModel(Uint8List model) {
    if (_disposed) return;
    _commands.send(_SileroModelMsg(TransferableTypedData.fromList([model])));
  }

  void resetCapture() {
    if (_disposed) return;
    _commands.send(const _ResetCaptureMsg());
  }

  void pushRx({
    required int key,
    required int streamId,
    required int packetNo,
    required Uint8List encoded,
    double gain = 1,
    List<int> frameSizes = const [],
    int framesPerPacket = 1,
  }) {
    if (_disposed) return;
    _commands.send(
      _RxPacketMsg(
        key,
        streamId,
        encoded,
        packetNo,
        gain,
        frameSizes,
        framesPerPacket,
      ),
    );
  }

  void resetTx() {
    if (_disposed) return;
    _commands.send(const _ResetTxMsg());
  }

  void resetRx(int key) {
    if (_disposed) return;
    _commands.send(_ResetRxMsg(key));
  }

  void resetRxAll() {
    if (_disposed) return;
    _commands.send(const _ResetRxAllMsg());
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _commands.send(const _ShutdownMsg());
    await _sub?.cancel();
    _sub = null;
    _responses.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

class _StatusSlot {
  Completer<_MediaStartedMsg>? media;
  Completer<_AudioStatusMsg>? pending;
  Completer<_StatsReplyMsg>? stats;
  Completer<_UdpStatusMsg>? udp;
  Completer<_RecordingReplyMsg>? recording;
}
