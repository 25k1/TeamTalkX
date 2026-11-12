import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../diagnostics/log.dart';
import 'pcm_resampler.dart';
import 'silero_vad.dart';
import 'voice_detector.dart';

class SileroVoiceDetector implements VoiceDetector {
  SileroVoiceDetector({this.modelBytes, this.nativeLibrary});

  final Uint8List? modelBytes;

  final DynamicLibrary? nativeLibrary;

  static const _asset = 'assets/vad/silero_vad_v6_2.bin';

  static Future<Uint8List> loadModelBytes() async {
    final data = await rootBundle.load(_asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static const _releaseHang = Duration(milliseconds: 400);

  static final int _releaseChunks =
      (_releaseHang.inMicroseconds /
              (SileroVad.chunkSize *
                  Duration.microsecondsPerSecond ~/
                  vadSampleRate))
          .round();

  SileroVad? _vad;
  bool _startFailed = false;
  bool _disposed = false;
  bool _speaking = false;
  int _quietChunks = 0;

  @override
  bool get needsSuppressorProbability => false;

  @override
  Duration get releaseHold => Duration.zero;

  @override
  bool accept(
    Uint8List pcm, {
    required double? probability,
    required int sampleRate,
    required int channels,
    required int level,
    required bool currentlyActive,
  }) {
    final vad = _open();
    if (vad == null) return false;
    final mono16k = resampleForVad(
      pcm,
      sampleRate: sampleRate,
      channels: channels,
    );
    final positive = positiveThreshold(level);
    final negative = negativeThreshold(level);
    for (final p in vad.feed(
      mono16k.buffer.asInt16List(
        mono16k.offsetInBytes,
        mono16k.lengthInBytes ~/ 2,
      ),
    )) {
      if (p >= positive) {
        _speaking = true;
        _quietChunks = 0;
      } else if (_speaking &&
          p < negative &&
          ++_quietChunks >= _releaseChunks) {
        _speaking = false;
        _quietChunks = 0;
      }
    }
    return _speaking;
  }

  SileroVad? _open() {
    if (_disposed || _startFailed) return _vad;
    if (_vad != null) return _vad;
    final bytes = modelBytes;
    try {
      if (bytes == null) throw StateError('No Silero weights');
      return _vad = SileroVad(bytes, library: nativeLibrary);
    } on Object catch (e, st) {
      _startFailed = true;
      appLog.w('voice', 'Silero voice detection failed to start', e, st);
      return null;
    }
  }

  @visibleForTesting
  static double positiveThreshold(int level) =>
      0.15 + (level.clamp(0, 20) / 20) * 0.8;

  @visibleForTesting
  static double negativeThreshold(int level) =>
      (positiveThreshold(level) - 0.15).clamp(0.05, 0.95);

  @visibleForTesting
  bool get isListening => _vad != null;

  @override
  void reset() {
    _speaking = false;
    _quietChunks = 0;
    _vad?.reset();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _vad?.dispose();
    _vad = null;
  }
}
