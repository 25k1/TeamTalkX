import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../diagnostics/log.dart';
import 'dsp/pcm_resampler.dart';
import 'media_source.dart';
import 'native_engine.dart';

Int16List decodeForMixer(MediaSource source) {
  final out = BytesBuilder(copy: false);
  List<StreamingResampler> resamplers = const [];
  var rate = 0;
  while (true) {
    final chunk = source.read(48000);
    if (chunk == null) break;
    final channels = math.max(1, source.channels);
    if (source.sampleRate != rate) {
      rate = source.sampleRate;
      resamplers = [
        StreamingResampler(rate, 48000),
        StreamingResampler(rate, 48000),
      ];
    }
    final frames = chunk.length ~/ channels;
    final left = Int16List(frames);
    final right = Int16List(frames);
    for (var f = 0; f < frames; f++) {
      left[f] = chunk[f * channels];
      right[f] = chunk[f * channels + math.min(1, channels - 1)];
    }
    final l = resamplers[0].process(left);
    final r = resamplers[1].process(right);
    final n = math.min(l.length, r.length);
    final stereo = Int16List(n * 2);
    for (var i = 0; i < n; i++) {
      stereo[i * 2] = l[i];
      stereo[i * 2 + 1] = r[i];
    }
    out.add(stereo.buffer.asUint8List());
  }
  final bytes = out.takeBytes();
  return bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
}

abstract interface class SpeakerSink {
  int writeSpeaker(int key, Int16List pcm, {double gain});
  int speakerQueued(int key);
  void removeSpeaker(int key);
}

class NativeSpeakerSink implements SpeakerSink {
  NativeSpeakerSink(this.engine);
  final NativeAudioEngine engine;

  @override
  int writeSpeaker(int key, Int16List pcm, {double gain = 1}) =>
      engine.writeSpeaker(key, pcm, gain: gain);

  @override
  int speakerQueued(int key) => engine.speakerQueued(key);

  @override
  void removeSpeaker(int key) => engine.removeSpeaker(key);
}

class _Voice {
  _Voice(this.key, this.pcm, this.gain);
  final int key;
  final Int16List pcm;
  final double gain;
  int position = 0;
}

class SoundEffectsMixer {
  SoundEffectsMixer(this.sink, {this.maxVoices = 4});

  final SpeakerSink sink;
  final int maxVoices;

  static const _aheadSamples = 60 * 96;
  static const _chunkSamples = 20 * 96;

  final _voices = <_Voice>[];
  int _nextKey = 0;

  bool get idle => _voices.isEmpty;

  void play(Int16List pcm, {double gain = 1}) {
    if (pcm.isEmpty) return;
    if (_voices.length >= maxVoices) {
      sink.removeSpeaker(_voices.removeAt(0).key);
    }
    _nextKey = _nextKey % 64 + 1;
    _voices.add(_Voice(_nextKey, pcm, gain));
    tick();
  }

  void tick() {
    for (final v in List.of(_voices)) {
      var queued = sink.speakerQueued(v.key);
      while (queued < _aheadSamples && v.position < v.pcm.length) {
        final end = math.min(v.position + _chunkSamples, v.pcm.length);
        sink.writeSpeaker(
          v.key,
          Int16List.sublistView(v.pcm, v.position, end),
          gain: v.gain,
        );
        queued += end - v.position;
        v.position = end;
      }
      if (v.position >= v.pcm.length && queued == 0) {
        sink.removeSpeaker(v.key);
        _voices.remove(v);
      }
    }
  }

  void stopAll() {
    for (final v in _voices) {
      sink.removeSpeaker(v.key);
    }
    _voices.clear();
  }
}

class _PlayMsg {
  const _PlayMsg(this.path, this.gain);
  final String path;
  final double gain;
}

class _OutputMsg {
  const _OutputMsg({required this.voiceCall, required this.deviceId});
  final bool voiceCall;
  final int deviceId;
}

class _StopMsg {
  const _StopMsg();
}

class _BusyMsg {
  const _BusyMsg(this.busy);
  final bool busy;
}

class _LogMsg {
  const _LogMsg(this.message, this.error);
  final String message;
  final String? error;
}

class SoundEffects {
  SoundEffects._(this._isolate, this._commands, this._responses);

  static Future<SoundEffects> spawn() async {
    final responses = ReceivePort();
    final isolate = await Isolate.spawn(_main, responses.sendPort);
    final ready = Completer<SendPort>();
    SoundEffects? self;
    responses.listen((msg) {
      if (msg is SendPort && !ready.isCompleted) {
        ready.complete(msg);
      } else if (msg is _BusyMsg) {
        self?._busy.add(msg.busy);
      } else if (msg is _LogMsg) {
        appLog.w('sound', msg.message, msg.error);
      }
    });
    return self = SoundEffects._(isolate, await ready.future, responses);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final _busy = StreamController<bool>.broadcast();

  Stream<bool> get busy => _busy.stream;

  void play(String path, {double gain = 1}) =>
      _commands.send(_PlayMsg(path, gain));

  void stopAll() => _commands.send(const _StopMsg());

  void setOutput({required bool voiceCall, int deviceId = 0}) =>
      _commands.send(_OutputMsg(voiceCall: voiceCall, deviceId: deviceId));

  void dispose() {
    _responses.close();
    unawaited(_busy.close());
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

const idleTimeout = Duration(seconds: 10);

void _main(SendPort root) {
  final commands = ReceivePort();
  root.send(commands.sendPort);
  NativeAudioEngine? engine;
  SoundEffectsMixer? mixer;
  Timer? timer;
  var idleSince = DateTime.now();
  var playing = false;
  var busy = false;
  void setBusy(bool now) {
    if (now == busy) return;
    busy = now;
    root.send(_BusyMsg(now));
  }

  var output = const _OutputMsg(voiceCall: false, deviceId: 0);
  final cache = <String, Int16List>{};

  void log(String message, [Object? error]) =>
      root.send(_LogMsg(message, error?.toString()));

  void tick() {
    final m = mixer;
    if (m == null) return;
    m.tick();
    setBusy(!m.idle);
    if (!m.idle) {
      idleSince = DateTime.now();
    } else if (DateTime.now().difference(idleSince) > idleTimeout) {
      timer?.cancel();
      timer = null;
      engine?.stopPlayback();
      playing = false;
    }
  }

  Int16List? decode(String path) {
    final cached = cache.remove(path);
    if (cached != null) return cache[path] = cached;
    try {
      final source = openMediaSource(path);
      try {
        final pcm = decodeForMixer(source);
        if (cache.length >= 32) cache.remove(cache.keys.first);
        return cache[path] = pcm;
      } finally {
        source.close();
      }
    } on Exception catch (e) {
      log('Event sound $path could not be decoded', e);
      return null;
    }
  }

  commands.listen((msg) {
    if (msg is _PlayMsg) {
      final pcm = decode(msg.path);
      if (pcm == null) return;
      try {
        engine ??= NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
      } on Object catch (e) {
        log('No engine for event sounds', e);
        return;
      }
      final e = engine!
        ..setOutput(voiceCall: output.voiceCall, deviceId: output.deviceId);
      mixer ??= SoundEffectsMixer(NativeSpeakerSink(e));
      if (!playing) {
        final result = e.startPlayback();
        playing = result == 0;
        if (!playing) log('Event sound output could not start ($result)');
      }
      mixer!.play(pcm, gain: msg.gain);
      setBusy(true);
      idleSince = DateTime.now();
      timer ??= Timer.periodic(const Duration(milliseconds: 10), (_) => tick());
    } else if (msg is _OutputMsg) {
      output = msg;
      engine?.setOutput(voiceCall: msg.voiceCall, deviceId: msg.deviceId);
    } else if (msg is _StopMsg) {
      mixer?.stopAll();
    }
  });
}
