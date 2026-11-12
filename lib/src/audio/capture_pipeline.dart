import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../domain/capture_settings.dart';
import 'dsp/agc.dart';
import 'dsp/noise_suppression.dart';
import 'dsp/silero_voice_detector.dart';
import 'dsp/voice_activity_detector.dart';
import 'dsp/voice_detector.dart';

class CaptureFrame {
  const CaptureFrame(this.pcm, this.gain);

  final Uint8List pcm;
  final double gain;
}

class CaptureOutput {
  const CaptureOutput(this.frames, this.voice);

  static const empty = CaptureOutput([], null);

  final List<CaptureFrame> frames;

  final bool? voice;
}

typedef VoiceDetectorFactory =
    VoiceDetector Function(VoiceDetectorKind kind, Uint8List? sileroModel);

VoiceDetector _defaultDetector(VoiceDetectorKind kind, Uint8List? model) =>
    switch (kind) {
      VoiceDetectorKind.silero => SileroVoiceDetector(modelBytes: model),
      VoiceDetectorKind.rnnoise => VoiceActivityDetector(),
    };

class CapturePipeline {
  CapturePipeline({
    NoiseSuppressor Function()? createSuppressor,
    VoiceDetectorFactory? createDetector,
    this.preRoll = const Duration(milliseconds: 200),
  }) : _createSuppressor = createSuppressor ?? NoiseSuppressor.new,
       _createDetector = createDetector ?? _defaultDetector;

  final Duration preRoll;

  final NoiseSuppressor Function() _createSuppressor;
  final VoiceDetectorFactory _createDetector;

  CaptureSettings? _settings;
  NoiseSuppressor? _suppressor;
  VoiceDetector? _detector;
  VoiceDetectorKind? _detectorKind;
  Uint8List? _sileroModel;

  final AutoGainControl _agc = AutoGainControl();
  bool _agcEngaged = false;

  final Queue<Uint8List> _preRoll = Queue();
  int _preRollBytes = 0;

  CaptureSettings? get settings => _settings;

  set sileroModel(Uint8List? bytes) {
    _sileroModel = bytes;
    if (_detectorKind == VoiceDetectorKind.silero) _dropDetector();
  }

  void configure(CaptureSettings settings) {
    final previous = _settings;
    _settings = settings;
    if (previous == null ||
        previous.sampleRate != settings.sampleRate ||
        previous.channels != settings.channels) {
      _clearPreRoll();
    }
    if (settings.needsDenoiser) {
      (_suppressor ??= _createSuppressor()).configure(
        sampleRate: settings.sampleRate,
        channels: settings.channels,
        wet: settings.noiseSuppressionLevel,
      );
    }
    if (_detectorKind != null && _detectorKind != settings.detector) {
      _dropDetector();
    }
  }

  CaptureOutput process(
    Uint8List pcm, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) {
    final settings = _settings;
    if (settings == null || pcm.isEmpty) return CaptureOutput.empty;

    var processed = pcm;
    double? probability;
    if (settings.needsDenoiser) {
      final result = _suppressor!.process(pcm);
      probability = result.voiceProbability;
      if (settings.noiseSuppression) processed = result.pcm;
    }

    bool? voice;
    if (settings.voiceDetection) {
      final detector = _detector ??= _newDetector(settings.detector);
      voice = detector.accept(
        pcm,
        probability: probability,
        sampleRate: settings.sampleRate,
        channels: settings.channels,
        level: settings.voiceLevel,
        currentlyActive: voiceActive,
      );
    }

    final frames = <CaptureFrame>[];
    if (transmit) {
      if (flushPreRoll) {
        for (final frame in _preRoll) {
          frames.add(CaptureFrame(frame, _gainFor(settings, frame)));
        }
      }
      _clearPreRoll();
      if (processed.isNotEmpty) {
        frames.add(CaptureFrame(processed, _gainFor(settings, processed)));
      }
    } else if (settings.voiceDetection && processed.isNotEmpty) {
      _preRoll.addLast(processed);
      _preRollBytes += processed.lengthInBytes;
      final maxBytes =
          settings.sampleRate *
          settings.channels *
          2 *
          preRoll.inMilliseconds ~/
          1000;
      while (_preRollBytes > maxBytes && _preRoll.length > 1) {
        _preRollBytes -= _preRoll.removeFirst().lengthInBytes;
      }
    }
    return CaptureOutput(frames, voice);
  }

  void reset() {
    _suppressor?.reset();
    _detector?.reset();
    _clearPreRoll();
    _agcEngaged = false;
  }

  Future<void> dispose() async {
    _suppressor?.dispose();
    _suppressor = null;
    final detector = _detector;
    _detector = null;
    _detectorKind = null;
    await detector?.dispose();
  }

  VoiceDetector _newDetector(VoiceDetectorKind kind) {
    _detectorKind = kind;
    return _createDetector(kind, _sileroModel);
  }

  void _dropDetector() {
    final detector = _detector;
    _detector = null;
    _detectorKind = null;
    if (detector != null) unawaited(detector.dispose());
  }

  double _gainFor(CaptureSettings settings, Uint8List pcm) {
    if (!settings.agc) {
      _agcEngaged = false;
      return settings.gain;
    }
    if (!_agcEngaged) {
      _agcEngaged = true;
      _agc.reset();
    }
    _agc.targetRms = AutoGainControl.targetForGainPercent(
      settings.agcGainPercent,
    );
    return _agc.gainFor(pcm);
  }

  void _clearPreRoll() {
    _preRoll.clear();
    _preRollBytes = 0;
  }
}
