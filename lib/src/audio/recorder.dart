import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/recording.dart';
import 'recording_writers.dart';

typedef RecordingWriterFactory = RecordingWriter Function(int userId);

int _framesIn(int us) => us * recordingSampleRate ~/ 1000000;

class RecordingTimeline {
  RecordingTimeline(this.writer);

  final RecordingWriter writer;

  static const blockFrames = 960;
  static const _blockSamples = blockFrames * recordingChannels;

  final _blocks = <int, Int32List>{};

  int _written = 0;

  int get writtenFrames => _written * blockFrames;

  void mix(int frame, Int16List pcm, double gain) {
    final frames = pcm.length ~/ recordingChannels;
    for (var f = 0; f < frames; f++) {
      final at = frame + f;
      if (at < writtenFrames) continue;
      final block = _blocks.putIfAbsent(
        at ~/ blockFrames,
        () => Int32List(_blockSamples),
      );
      final i = (at % blockFrames) * recordingChannels;
      if (gain == 1.0) {
        block[i] += pcm[f * 2];
        block[i + 1] += pcm[f * 2 + 1];
      } else {
        block[i] += (pcm[f * 2] * gain).round();
        block[i + 1] += (pcm[f * 2 + 1] * gain).round();
      }
    }
  }

  bool flush(int frame, {int maxBlocks = maxBlocksPerFlush}) {
    final target = frame ~/ blockFrames;
    final end = math.min(target, _written + maxBlocks);
    if (end > _written) {
      final out = Int16List((end - _written) * _blockSamples);
      for (var b = _written; b < end; b++) {
        final block = _blocks.remove(b);
        if (block == null) continue;
        final base = (b - _written) * _blockSamples;
        for (var i = 0; i < _blockSamples; i++) {
          final s = block[i];
          out[base + i] = s > 32767 ? 32767 : (s < -32768 ? -32768 : s);
        }
      }
      _written = end;
      writer
        ..write(out)
        ..sync();
    }
    return _written >= target;
  }

  static const maxBlocksPerFlush = 250;

  int endFrame(int frame) {
    var end = frame ~/ blockFrames + 1;
    for (final b in _blocks.keys) {
      if (b + 1 > end) end = b + 1;
    }
    return end * blockFrames;
  }
}

class Recorder {
  Recorder({
    required this.mode,
    required this._open,
    required this._startUs,
    this.onWriterFailed,
  }) {
    if (mode == RecordingMode.mixed) _timeline(mixedRecordingUserId);
  }

  final RecordingMode mode;
  final RecordingWriterFactory _open;
  final int _startUs;

  final void Function(int userId, Object error)? onWriterFailed;

  final _timelines = <int, RecordingTimeline>{};
  final _failed = <int>{};
  final _cursors = <int, int>{};

  static final lagFrames = _framesIn(200000);

  static final holdFrames = _framesIn(500000);

  int _frameAt(int nowUs) => _framesIn(nowUs - _startUs);

  RecordingTimeline? _timeline(int userId) {
    if (_failed.contains(userId)) return null;
    final existing = _timelines[userId];
    if (existing != null) return existing;
    try {
      return _timelines[userId] = RecordingTimeline(_open(userId));
    } on Object catch (e) {
      _failed.add(userId);
      onWriterFailed?.call(userId, e);
      return null;
    }
  }

  Iterable<int> get users => _timelines.keys;

  void add(int key, Int16List pcm, int nowUs, {double gain = 1}) {
    if (pcm.isEmpty) return;
    final now = _frameAt(nowUs);
    var cursor = _cursors[key];
    if (cursor == null || cursor < now - lagFrames) cursor = now;
    final userId = mode == RecordingMode.mixed
        ? mixedRecordingUserId
        : key >> 8;
    _cursors[key] = cursor + pcm.length ~/ recordingChannels;
    final timeline = _timeline(userId);
    if (timeline == null) return;
    timeline.mix(cursor, pcm, gain);
  }

  void tick(int nowUs) {
    final upTo = _frameAt(nowUs) - holdFrames;
    if (upTo <= 0) return;
    for (final entry in _timelines.entries.toList()) {
      try {
        entry.value.flush(upTo);
      } on FileSystemException catch (e) {
        _fail(entry.key, e);
      }
    }
  }

  void _fail(int userId, Object error) {
    try {
      _timelines.remove(userId)?.writer.close();
    } on FileSystemException catch (_) {}
    _failed.add(userId);
    onWriterFailed?.call(userId, error);
  }

  Map<int, int>? _ends;

  bool finish(int nowUs) {
    final now = _frameAt(nowUs);
    final ends = _ends ??= {
      for (final MapEntry(:key, :value) in _timelines.entries)
        key: value.endFrame(now),
    };
    for (final entry in _timelines.entries.toList()) {
      try {
        if (entry.value.flush(ends[entry.key]!)) {
          _timelines.remove(entry.key);
          entry.value.writer.close();
        }
      } on FileSystemException catch (e) {
        _fail(entry.key, e);
      }
    }
    return _timelines.isEmpty;
  }
}
