part of '../audio_worker.dart';

class _CaptureJob {
  _CaptureJob(this._w);

  final _Worker _w;

  final tx = _TxState();
  final pipeline = CapturePipeline();
  Timer? _timer;
  var _frameSamples = 0;
  final _captured = <int>[];
  _CaptureStateMsg? _state;
  var _flushPending = false;

  void setState(_CaptureStateMsg msg) {
    if (msg.flushPreRoll) _flushPending = true;
    _state = msg;
  }

  void setProtection(LossProtection value) {
    if (tx.protection == value) return;
    tx
      ..reset()
      ..protection = value;
  }

  void reset() {
    pipeline.reset();
    _flushPending = false;
  }

  void start(_StartCaptureMsg msg) {
    final e = _w.output.engine();
    if (e == null) return;
    final output = _w.output.settings;
    e.setOutput(voiceCall: output.voiceCall, deviceId: output.deviceId);
    stop();
    final result = e.startCapture(
      audioSource: msg.audioSource,
      sampleRate: msg.sampleRate,
      channels: msg.channels,
    );
    if (result != 0 && result != engineNoDevice) {
      _w.log(LogLevel.error, 'The microphone could not be started ($result)');
      _w.rootPort.send(_CaptureErrorMsg(result));
      return;
    }
    _frameSamples = msg.sampleRate ~/ 50 * msg.channels;
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => _read());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _w.output.native?.stopCapture();
    _captured.clear();
  }

  void _read() {
    final samples = _w.output.native?.readCapture();
    if (samples == null || samples.isEmpty || _frameSamples <= 0) return;
    _captured.addAll(samples);
    while (_captured.length >= _frameSamples) {
      final frame = Int16List.fromList(_captured.sublist(0, _frameSamples));
      _captured.removeRange(0, _frameSamples);
      _processFrame(frame.buffer.asUint8List());
    }
  }

  void _processFrame(Uint8List pcm) {
    final state = _state;
    final testing = _w.micTest.test != null;
    final transmit = testing || (state?.transmit ?? false);
    final flush = transmit && _flushPending;
    if (flush) _flushPending = false;
    final out = pipeline.process(
      pcm,
      transmit: transmit,
      flushPreRoll: flush,
      voiceActive: state?.voiceActive ?? false,
    );
    final settings = pipeline.settings;
    if (testing) {
      _w.micTest.frames(out.frames);
    } else if (state != null && settings != null && out.frames.isNotEmpty) {
      final packets = <Uint8List>[];
      for (final frame in out.frames) {
        _w.recording.recorder?.add(
          (state.userId << 8) | packetKindVoice,
          _toRecording(frame, settings.sampleRate, settings.channels),
          _w.clock.elapsedMicroseconds,
        );
        packets.addAll(
          _encodeTx(
            tx,
            _TxFrame(
              streamId: state.streamId,
              userId: state.userId,
              channelId: state.channelId,
              pcm: frame.pcm,
              sampleRate: settings.sampleRate,
              captureChannels: settings.channels,
              gain: frame.gain,
              outputChannel: settings.outputChannel,
              config: state.config,
            ),
            _w.log,
          ),
        );
      }
      _w.network.send(packets, state.userId, packetKindVoice);
    }
    final voice = out.voice;
    if (voice != null) _w.rootPort.send(_CaptureVoiceMsg(voice));
  }
}

class _TxState {
  AudioPacketizer? packetizer;
  TxCodecConfig? config;
  int outChannels = 0;
  Int16List scratch = Int16List(0);
  LossProtection protection = LossProtection.channel;

  void reset() {
    packetizer?.dispose();
    packetizer = null;
    config = null;
    outChannels = 0;
  }
}

class _TxFrame {
  const _TxFrame({
    required this.streamId,
    required this.userId,
    required this.channelId,
    required this.pcm,
    required this.sampleRate,
    required this.captureChannels,
    required this.gain,
    required this.outputChannel,
    required this.config,
  });

  final int streamId;
  final int userId;
  final int channelId;
  final Uint8List pcm;
  final int sampleRate;
  final int captureChannels;
  final double gain;
  final int outputChannel;
  final TxCodecConfig config;
}

Int16List _toRecording(CaptureFrame frame, int sampleRate, int channels) {
  final bd = ByteData.sublistView(frame.pcm);
  final pcm = Int16List(frame.pcm.lengthInBytes ~/ 2);
  final gain = frame.gain;
  for (var i = 0; i < pcm.length; i++) {
    final s = bd.getInt16(i * 2, Endian.little);
    pcm[i] = gain == 1.0 ? s : (s * gain).round().clamp(-32768, 32767);
  }
  return resamplePcm(
    pcm,
    sampleRate,
    channels,
    recordingSampleRate,
    recordingChannels,
  );
}

List<Uint8List> _encodeTx(_TxState tx, _TxFrame msg, _WorkerLog log) {
  final config = msg.config;
  final stereoOut =
      !config.isSpeex &&
      msg.captureChannels == 2 &&
      msg.outputChannel != 0 &&
      msg.outputChannel != 1;
  final outChannels = stereoOut ? 2 : 1;

  if (tx.config != config ||
      tx.packetizer == null ||
      tx.outChannels != outChannels) {
    tx.reset();
    try {
      tx.packetizer = AudioPacketizer(
        config: config,
        channels: outChannels,
        protection: tx.protection,
      );
      tx.config = config;
      tx.outChannels = outChannels;
    } on StateError catch (e) {
      log(LogLevel.error, 'Voice encoder creation failed', e);
      return const [];
    } on ArgumentError catch (e) {
      log(LogLevel.error, 'Voice encoder unavailable', e);
      return const [];
    }
  }
  final gain = msg.gain;

  final bd = ByteData.sublistView(msg.pcm);
  final frames = (msg.pcm.lengthInBytes ~/ 2) ~/ msg.captureChannels;
  if (frames == 0) return const [];
  if (tx.scratch.length < frames * outChannels) {
    tx.scratch = Int16List(frames * outChannels);
  }
  final captured = Int16List.sublistView(tx.scratch, 0, frames * outChannels);
  int clampGain(int s) =>
      gain == 1.0 ? s : (s * gain).round().clamp(-32768, 32767);
  for (var f = 0; f < frames; f++) {
    if (stereoOut) {
      captured[f * 2] = clampGain(bd.getInt16(f * 4, Endian.little));
      captured[f * 2 + 1] = clampGain(bd.getInt16(f * 4 + 2, Endian.little));
    } else if (msg.captureChannels == 2) {
      captured[f] = clampGain(
        bd.getInt16((f * 2 + msg.outputChannel) * 2, Endian.little),
      );
    } else {
      captured[f] = clampGain(bd.getInt16(f * 2, Endian.little));
    }
  }

  final pcm = msg.sampleRate == config.sampleRate
      ? captured
      : resamplePcm(
          captured,
          msg.sampleRate,
          outChannels,
          config.sampleRate,
          outChannels,
        );
  return tx.packetizer!.add(
    pcm,
    streamId: msg.streamId,
    userId: msg.userId,
    channelId: msg.channelId,
  );
}
