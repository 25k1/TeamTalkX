import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

const engineNoDevice = -1000;

final class _Stats extends Struct {
  @Int64()
  external int playbackRunning;
  @Int64()
  external int playbackSampleRate;
  @Int64()
  external int playbackBurstFrames;
  @Int64()
  external int playbackBufferFrames;
  @Int64()
  external int playbackXruns;
  @Int64()
  external int captureRunning;
  @Int64()
  external int captureSampleRate;
  @Int64()
  external int captureChannels;
  @Int64()
  external int captureXruns;
  @Int64()
  external int activeSpeakers;
  @Int64()
  external int speakerDropped;
  @Int64()
  external int captureOverflow;
  @Int64()
  external int renderedFrames;
  @Int64()
  external int lastError;
  @Double()
  external double playbackLatencyMs;
  @Double()
  external double captureLatencyMs;
}

class EngineStats {
  const EngineStats({
    required this.playbackRunning,
    required this.playbackSampleRate,
    required this.playbackBurstFrames,
    required this.playbackBufferFrames,
    required this.playbackXruns,
    required this.captureRunning,
    required this.captureSampleRate,
    required this.captureChannels,
    required this.captureXruns,
    required this.activeSpeakers,
    required this.speakerDropped,
    required this.captureOverflow,
    required this.renderedFrames,
    required this.lastError,
    required this.playbackLatencyMs,
    required this.captureLatencyMs,
  });

  final bool playbackRunning;
  final int playbackSampleRate;
  final int playbackBurstFrames;
  final int playbackBufferFrames;
  final int playbackXruns;
  final bool captureRunning;
  final int captureSampleRate;
  final int captureChannels;
  final int captureXruns;
  final int activeSpeakers;

  final int speakerDropped;

  final int captureOverflow;
  final int renderedFrames;

  final int lastError;

  final double playbackLatencyMs;
  final double captureLatencyMs;

  @override
  String toString() =>
      'playback ${playbackRunning ? 'on' : 'off'} ${playbackSampleRate}Hz '
      'burst $playbackBurstFrames buffer $playbackBufferFrames '
      'xruns $playbackXruns latency ${playbackLatencyMs.toStringAsFixed(1)}ms; '
      'capture ${captureRunning ? 'on' : 'off'} ${captureSampleRate}Hz '
      'x$captureChannels xruns $captureXruns '
      'latency ${captureLatencyMs.toStringAsFixed(1)}ms; '
      'speakers $activeSpeakers dropped $speakerDropped '
      'overflow $captureOverflow error $lastError';
}

typedef _CreateN = Pointer<Void> Function(Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int);
typedef _HandleN = Void Function(Pointer<Void>);
typedef _HandleD = void Function(Pointer<Void>);
typedef _StartN = Int32 Function(Pointer<Void>);
typedef _StartD = int Function(Pointer<Void>);
typedef _StartCaptureN = Int32 Function(Pointer<Void>, Int32, Int32, Int32);
typedef _StartCaptureD = int Function(Pointer<Void>, int, int, int);
typedef _ReadN = Int32 Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _ReadD = int Function(Pointer<Void>, Pointer<Int16>, int);
typedef _WriteN =
    Int32 Function(Pointer<Void>, Int32, Pointer<Int16>, Int32, Float);
typedef _WriteD = int Function(Pointer<Void>, int, Pointer<Int16>, int, double);
typedef _KeyN = Void Function(Pointer<Void>, Int32);
typedef _KeyD = void Function(Pointer<Void>, int);
typedef _OutputN = Void Function(Pointer<Void>, Int32, Int32);
typedef _OutputD = void Function(Pointer<Void>, int, int);
typedef _QueuedN = Int32 Function(Pointer<Void>, Int32);
typedef _QueuedD = int Function(Pointer<Void>, int);
typedef _GainN = Void Function(Pointer<Void>, Float);
typedef _GainD = void Function(Pointer<Void>, double);
typedef _StatsN = Void Function(Pointer<Void>, Pointer<_Stats>);
typedef _StatsD = void Function(Pointer<Void>, Pointer<_Stats>);
typedef _PcmN = Void Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _PcmD = void Function(Pointer<Void>, Pointer<Int16>, int);

class NativeAudioEngine {
  NativeAudioEngine({
    required this.sampleRate,
    required this.playbackChannels,
    DynamicLibrary? library,
  }) {
    final lib = library ?? openNativeAudio();
    _destroy = lib.lookupFunction<_HandleN, _HandleD>('tt_engine_destroy');
    _startPlayback = lib.lookupFunction<_StartN, _StartD>(
      'tt_engine_start_playback',
    );
    _stopPlayback = lib.lookupFunction<_HandleN, _HandleD>(
      'tt_engine_stop_playback',
    );
    _startPlaybackAsync = lib.lookupFunction<_HandleN, _HandleD>(
      'tt_engine_start_playback_async',
    );
    _startCapture = lib.lookupFunction<_StartCaptureN, _StartCaptureD>(
      'tt_engine_start_capture',
    );
    _stopCapture = lib.lookupFunction<_HandleN, _HandleD>(
      'tt_engine_stop_capture',
    );
    _readCapture = lib.lookupFunction<_ReadN, _ReadD>('tt_engine_read_capture');
    _writeSpeaker = lib.lookupFunction<_WriteN, _WriteD>(
      'tt_engine_write_speaker',
    );
    _removeSpeaker = lib.lookupFunction<_KeyN, _KeyD>(
      'tt_engine_remove_speaker',
    );
    _speakerQueued = lib.lookupFunction<_QueuedN, _QueuedD>(
      'tt_engine_speaker_queued',
    );
    _setOutput = lib.lookupFunction<_OutputN, _OutputD>('tt_engine_set_output');
    _setMasterGain = lib.lookupFunction<_GainN, _GainD>(
      'tt_engine_set_master_gain',
    );
    _getStats = lib.lookupFunction<_StatsN, _StatsD>('tt_engine_get_stats');
    _render = lib.lookupFunction<_PcmN, _PcmD>('tt_engine_render');
    _pushCapture = lib.lookupFunction<_PcmN, _PcmD>('tt_engine_push_capture');
    _engine = lib.lookupFunction<_CreateN, _CreateD>('tt_engine_create')(
      sampleRate,
      playbackChannels,
    );
    if (_engine == nullptr) throw StateError('tt_engine_create failed');
    _buffer = calloc<Int16>(_bufferSamples);
    _stats = calloc<_Stats>();
  }

  final int sampleRate;
  final int playbackChannels;

  static const _bufferSamples = 96000;

  late final _HandleD _destroy;
  late final _StartD _startPlayback;
  late final _HandleD _stopPlayback;
  late final _HandleD _startPlaybackAsync;
  late final _StartCaptureD _startCapture;
  late final _HandleD _stopCapture;
  late final _ReadD _readCapture;
  late final _WriteD _writeSpeaker;
  late final _KeyD _removeSpeaker;
  late final _QueuedD _speakerQueued;
  late final _GainD _setMasterGain;
  late final _OutputD _setOutput;
  late final _StatsD _getStats;
  late final _PcmD _render;
  late final _PcmD _pushCapture;
  late final Pointer<Void> _engine;
  late final Pointer<Int16> _buffer;
  late final Pointer<_Stats> _stats;
  bool _disposed = false;

  void _check() {
    if (_disposed) throw StateError('NativeAudioEngine disposed');
  }

  int startPlayback() {
    _check();
    return _startPlayback(_engine);
  }

  void stopPlayback() {
    if (!_disposed) _stopPlayback(_engine);
  }

  void startPlaybackAsync() {
    _check();
    _startPlaybackAsync(_engine);
  }

  int startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) {
    _check();
    return _startCapture(_engine, audioSource, sampleRate, channels);
  }

  void stopCapture() {
    if (!_disposed) _stopCapture(_engine);
  }

  Int16List readCapture([int maxSamples = _bufferSamples]) {
    _check();
    final n = _readCapture(
      _engine,
      _buffer,
      maxSamples.clamp(0, _bufferSamples),
    );
    return Int16List.fromList(_buffer.asTypedList(n));
  }

  int writeSpeaker(int key, Int16List pcm, {double gain = 1}) {
    _check();
    var accepted = 0;
    for (var offset = 0; offset < pcm.length; offset += _bufferSamples) {
      final end = (offset + _bufferSamples).clamp(0, pcm.length);
      final n = end - offset;
      _buffer.asTypedList(n).setRange(0, n, pcm, offset);
      final written = _writeSpeaker(_engine, key, _buffer, n, gain);
      if (written < 0) return accepted == 0 ? -1 : accepted;
      accepted += written;
      if (written < n) break;
    }
    return accepted;
  }

  int speakerQueued(int key) => _disposed ? 0 : _speakerQueued(_engine, key);

  void removeSpeaker(int key) {
    if (!_disposed) _removeSpeaker(_engine, key);
  }

  void setOutput({required bool voiceCall, int deviceId = 0}) {
    if (!_disposed) _setOutput(_engine, voiceCall ? 1 : 0, deviceId);
  }

  set masterGain(double gain) {
    if (!_disposed) _setMasterGain(_engine, gain);
  }

  EngineStats stats() {
    _check();
    _getStats(_engine, _stats);
    final s = _stats.ref;
    return EngineStats(
      playbackRunning: s.playbackRunning != 0,
      playbackSampleRate: s.playbackSampleRate,
      playbackBurstFrames: s.playbackBurstFrames,
      playbackBufferFrames: s.playbackBufferFrames,
      playbackXruns: s.playbackXruns,
      captureRunning: s.captureRunning != 0,
      captureSampleRate: s.captureSampleRate,
      captureChannels: s.captureChannels,
      captureXruns: s.captureXruns,
      activeSpeakers: s.activeSpeakers,
      speakerDropped: s.speakerDropped,
      captureOverflow: s.captureOverflow,
      renderedFrames: s.renderedFrames,
      lastError: s.lastError,
      playbackLatencyMs: s.playbackLatencyMs,
      captureLatencyMs: s.captureLatencyMs,
    );
  }

  Int16List render(int frames) {
    _check();
    final samples = frames * playbackChannels;
    if (samples > _bufferSamples) throw ArgumentError.value(frames, 'frames');
    _render(_engine, _buffer, frames);
    return Int16List.fromList(_buffer.asTypedList(samples));
  }

  void pushCapture(Int16List pcm) {
    _check();
    final n = pcm.length.clamp(0, _bufferSamples);
    _buffer.asTypedList(n).setRange(0, n, pcm);
    _pushCapture(_engine, _buffer, n);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_engine);
    calloc
      ..free(_buffer)
      ..free(_stats);
  }
}
