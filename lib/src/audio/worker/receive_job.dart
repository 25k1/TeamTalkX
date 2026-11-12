part of '../audio_worker.dart';

class _ReceiveJob {
  _ReceiveJob(this._w);

  final _Worker _w;

  final streams = <int, _RxStream>{};
  TxCodecConfig codec = _defaultRxCodec;
  VoiceQuality quality = const VoiceQuality();
  double mediaGain = 1.0;
  var _normalize = false;
  var _speakerSlotsLogged = false;

  Timer? _playoutTimer;
  var _stretchUnavailable = false;

  void setQuality(VoiceQuality value) {
    quality = value;
    for (final s in streams.values) {
      s.setQuality(value);
    }
  }

  void setNormalize({required bool enabled}) {
    _normalize = enabled;
    if (!_normalize) {
      for (final s in streams.values) {
        s.normalizer.reset();
      }
    }
  }

  _StatsReplyMsg stats() {
    final e = _w.output.native;
    return _StatsReplyMsg(e?.stats(), [
      for (final MapEntry(:key, value: stream) in streams.entries)
        PlayoutStats(
          key: key,
          targetMs: stream.buffer.targetMs,
          jitterMs: stream.buffer.jitterMs,
          bufferedMs:
              stream.buffer.pendingMs +
              (_w.output.playback && e != null
                  ? e.speakerQueued(key) / _rxSamplesPerMs
                  : stream.virtualQueuedMs),
          speed: stream.buffer.speed,
          concealed: stream.buffer.concealed,
          late: stream.buffer.late,
          catchUpMs: stream.buffer.catchUpMs,
          slowDownMs: stream.buffer.slowDownMs,
          recovered: stream.recovered,
        ),
    ]);
  }

  void reset(int key) {
    streams.remove(key)?.dispose();
    _w.output.native?.removeSpeaker(key);
  }

  void dispose() {
    for (final key in streams.keys) {
      _w.output.native?.removeSpeaker(key);
    }
    for (final s in streams.values) {
      s.dispose();
    }
    streams.clear();
  }

  void _playoutStream(int key, _RxStream stream, int nowUs) {
    final e = _w.output.native;
    final device = _w.output.playback && e != null;
    final double queuedMs;
    if (device) {
      queuedMs = e.speakerQueued(key) / _rxSamplesPerMs;
    } else {
      final elapsedMs = (nowUs - stream.lastTickUs) / 1000;
      stream.virtualQueuedMs = math.max(0, stream.virtualQueuedMs - elapsedMs);
      queuedMs = stream.virtualQueuedMs;
    }
    stream.lastTickUs = nowUs;

    final buffer = stream.buffer;
    var pcm = buffer.pull(nowUs, queuedMs);
    final ended = buffer.takeEnded();
    stream.reportFailures(key, _w.log);
    final level =
        (_normalize && pcm != null ? stream.normalizer.update(pcm) : 1.0) *
        ((key & 0xFF) == packetKindMediaFileAudio ? mediaGain : 1.0);
    final recorder = _w.recording.recorder;
    if (!device) {
      if (pcm == null) return;
      recorder?.add(key, pcm, nowUs, gain: stream.gain * level);
      stream.virtualQueuedMs += pcm.length / _rxSamplesPerMs;
      _w.rootPort.send(
        RxDecoded(key, level == 1.0 ? pcm : _scaled(pcm, level)),
      );
      return;
    }

    var stretcher = stream.stretcher;
    if (stretcher == null && !_stretchUnavailable) {
      try {
        stretcher = stream.stretcher = TimeStretcher();
      } on ArgumentError catch (err) {
        _stretchUnavailable = true;
        _w.log(LogLevel.warning, 'Time-stretching unavailable', err);
      } on StateError catch (err) {
        _stretchUnavailable = true;
        _w.log(LogLevel.warning, 'Time-stretching unavailable', err);
      }
    }
    if (stretcher != null) {
      if (pcm != null) pcm = stretcher.process(pcm, buffer.speed);
      if (ended) {
        final rest = stretcher.flush();
        if (rest.isNotEmpty) pcm = _join(pcm, rest);
      }
    }
    if (pcm == null || pcm.isEmpty) return;
    recorder?.add(key, pcm, nowUs, gain: stream.gain * level);
    _w.output.wake(e);
    if (e.writeSpeaker(key, pcm, gain: stream.gain * level) < 0 &&
        !_speakerSlotsLogged) {
      _speakerSlotsLogged = true;
      _w.log(LogLevel.warning, 'More speakers than the mixer has slots');
    }
  }

  void _playout() {
    _w.output.checkStarted();
    final nowUs = _w.clock.elapsedMicroseconds;
    streams.forEach((key, stream) => _playoutStream(key, stream, nowUs));
  }

  void receive(_RxPacketMsg msg) {
    if (!_pushRx(
      streams,
      msg,
      codec,
      quality,
      _w.clock.elapsedMicroseconds,
      _w.log,
    )) {
      return;
    }
    _playoutTimer ??= Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _playout(),
    );
    final e = _w.output.native;
    if (_w.output.playback && e != null) _w.output.wake(e);
    _playoutStream(msg.key, streams[msg.key]!, _w.clock.elapsedMicroseconds);
  }

  void stopPlayout() => _playoutTimer?.cancel();
}

class _RxAudio {
  const _RxAudio(this.encoded, this.frameSizes, this.framesPerPacket);
  final Uint8List encoded;
  final List<int> frameSizes;
  final int framesPerPacket;
}

const _rxSamplesPerMs = 48 * 2;

Int16List _scaled(Int16List pcm, double gain) => Int16List.fromList([
  for (final s in pcm) (s * gain).round().clamp(-32768, 32767),
]);

Int16List _join(Int16List? a, Int16List b) {
  if (a == null || a.isEmpty) return b;
  return Int16List(a.length + b.length)
    ..setAll(0, a)
    ..setAll(a.length, b);
}

const _defaultRxCodec = TxCodecConfig(
  sampleRate: 48000,
  channels: 2,
  bitrate: 0,
);

VoiceFrameDecoder _decoderFor(TxCodecConfig codec, VoiceQuality quality) =>
    (codec.isSpeex
          ? SpeexVoiceDecoder(codec.speexBandMode)
          : OpusVoiceDecoder())
      ..setQuality(quality);

(AudioCodecType, int) _decoderKey(TxCodecConfig codec) =>
    (codec.isSpeex ? codec.codec : AudioCodecType.opus, codec.speexBandMode);

class _RxStream {
  _RxStream(TxCodecConfig codec, this.quality)
    : _codecKey = _decoderKey(codec),
      decoder = _decoderFor(codec, quality) {
    buffer = PlayoutBuffer<_RxAudio>(decode: _decode, plc: _conceal);
  }

  VoiceQuality quality;

  int recovered = 0;

  Int16List _conceal(_RxAudio? next, int packetsAhead, int samplesPerChannel) {
    final frames = next == null
        ? null
        : splitAudioFrames(
            next.encoded,
            next.frameSizes,
            framesPerPacket: next.framesPerPacket,
          );
    final pcm = decoder.recover(
      frames == null || frames.isEmpty ? null : frames.first,
      packetsAhead * samplesPerChannel,
      samplesPerChannel,
    );
    if (decoder.lastRecovered) recovered++;
    return pcm;
  }

  void setQuality(VoiceQuality value) {
    quality = value;
    decoder.setQuality(value);
  }

  (AudioCodecType, int) _codecKey;
  VoiceFrameDecoder decoder;
  late PlayoutBuffer<_RxAudio> buffer;

  TimeStretcher? stretcher;

  final normalizer = PlaybackNormalizer();

  double gain = 1;

  double virtualQueuedMs = 0;
  int lastTickUs = 0;

  Int16List _decode(_RxAudio audio) {
    final frames = splitAudioFrames(
      audio.encoded,
      audio.frameSizes,
      framesPerPacket: audio.framesPerPacket,
    );
    if (frames == null) {
      throw const FormatException('Frame sizes do not match the audio');
    }
    if (frames.length == 1) return decoder.decode(frames.single);
    final parts = [for (final frame in frames) decoder.decode(frame)];
    final out = Int16List(parts.fold(0, (n, p) => n + p.length));
    var off = 0;
    for (final part in parts) {
      out.setAll(off, part);
      off += part.length;
    }
    return out;
  }

  int streamId = 0;

  int reportedFailures = 0;

  void reportFailures(int key, _WorkerLog log) {
    final failures = buffer.decodeFailures;
    if (failures <= reportedFailures) return;
    if (reportedFailures == 0) {
      log(
        LogLevel.warning,
        'Voice decoding failed for stream $key',
        buffer.lastFailure,
      );
    }
    reportedFailures = failures;
  }

  void startStream(int newStreamId, TxCodecConfig codec) {
    final key = _decoderKey(codec);
    if (streamId == newStreamId && _codecKey == key) return;
    final next = _decoderFor(codec, quality);
    streamId = newStreamId;
    _codecKey = key;
    buffer.reset();
    decoder.dispose();
    decoder = next;
    stretcher?.dispose();
    stretcher = null;
  }

  void dispose() {
    buffer.reset();
    decoder.dispose();
    stretcher?.dispose();
    stretcher = null;
  }
}

bool _pushRx(
  Map<int, _RxStream> streams,
  _RxPacketMsg msg,
  TxCodecConfig codec,
  VoiceQuality quality,
  int nowUs,
  _WorkerLog log,
) {
  if (msg.encoded.isEmpty) return false;
  var stream = streams[msg.key];
  try {
    if (stream == null) {
      stream = _RxStream(codec, quality)..lastTickUs = nowUs;
      streams[msg.key] = stream;
    }
    stream.startStream(msg.streamId, codec);
  } on StateError catch (e) {
    log(LogLevel.error, 'Voice decoder creation failed', e);
    return false;
  } on ArgumentError catch (e) {
    log(LogLevel.error, 'Voice decoder unavailable', e);
    return false;
  }
  stream
    ..gain = msg.gain
    ..buffer.push(
      msg.packetNo,
      _RxAudio(msg.encoded, msg.frameSizes, msg.framesPerPacket),
      nowUs,
    );
  return true;
}
