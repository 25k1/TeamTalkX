import 'dart:typed_data';

import '../../diagnostics/log.dart';
import 'pcm_resampler.dart';
import 'rnnoise.dart';

class NoiseSuppressionResult {
  const NoiseSuppressionResult({required this.pcm, this.voiceProbability});

  final Uint8List pcm;

  final double? voiceProbability;
}

class NoiseSuppressor {
  NoiseSuppressor({RnnoiseDenoiser Function()? createDenoiser})
    : _createDenoiser = createDenoiser ?? RnnoiseDenoiser.new;

  static const _rate = 48000;

  final RnnoiseDenoiser Function() _createDenoiser;
  List<_Channel> _channels = const [];
  int _sampleRate = 0;
  double _wet = 1;
  bool _unavailable = false;

  int get sampleRate => _sampleRate;
  int get channels => _channels.length;

  void configure({
    required int sampleRate,
    required int channels,
    required double wet,
  }) {
    _wet = wet.clamp(0, 1);
    if (sampleRate == _sampleRate && channels == _channels.length) return;
    _disposeChannels();
    _sampleRate = sampleRate;
    if (_unavailable) return;
    try {
      _channels = [
        for (var c = 0; c < channels; c++)
          _Channel(_createDenoiser(), sampleRate, _rate),
      ];
    } on ArgumentError catch (e) {
      _unavailable = true;
      _disposeChannels();
      appLog.w('voice', 'Noise suppression unavailable', e);
    } on StateError catch (e) {
      _unavailable = true;
      _disposeChannels();
      appLog.w('voice', 'Noise suppression unavailable', e);
    }
  }

  NoiseSuppressionResult process(Uint8List pcm) {
    final channels = _channels;
    if (channels.isEmpty) return NoiseSuppressionResult(pcm: pcm);
    final samples = Int16List.view(
      pcm.buffer,
      pcm.offsetInBytes,
      pcm.lengthInBytes ~/ 2,
    );
    final count = channels.length;
    final frames = samples.length ~/ count;
    double? probability;
    for (var c = 0; c < count; c++) {
      final input = Int16List(frames);
      for (var f = 0; f < frames; f++) {
        input[f] = samples[f * count + c];
      }
      final p = channels[c].process(input, _wet);
      if (p != null && (probability == null || p > probability)) {
        probability = p;
      }
    }

    var ready = channels.first.output.length;
    for (final channel in channels.skip(1)) {
      if (channel.output.length < ready) ready = channel.output.length;
    }
    final out = Int16List(ready * count);
    for (var c = 0; c < count; c++) {
      final output = channels[c].output;
      for (var f = 0; f < ready; f++) {
        out[f * count + c] = output[f];
      }
      output.removeRange(0, ready);
    }
    return NoiseSuppressionResult(
      pcm: out.buffer.asUint8List(),
      voiceProbability: probability,
    );
  }

  void reset() {
    for (final channel in _channels) {
      channel.reset();
    }
  }

  void dispose() => _disposeChannels();

  void _disposeChannels() {
    for (final channel in _channels) {
      channel.denoiser.dispose();
    }
    _channels = const [];
  }
}

class _Channel {
  _Channel(this.denoiser, int rate, int denoiserRate)
    : _up = StreamingResampler(rate, denoiserRate),
      _down = StreamingResampler(denoiserRate, rate);

  final RnnoiseDenoiser denoiser;
  final StreamingResampler _up;
  final StreamingResampler _down;
  final _pending = <int>[];
  final output = <int>[];
  final _frame = Int16List(RnnoiseDenoiser.frameSize);

  double? process(Int16List input, double wet) {
    _pending.addAll(_up.process(input));
    double? probability;
    const size = RnnoiseDenoiser.frameSize;
    while (_pending.length >= size) {
      _frame.setAll(0, _pending.getRange(0, size));
      _pending.removeRange(0, size);
      final p = denoiser.process(_frame, wet: wet);
      if (probability == null || p > probability) probability = p;
      output.addAll(_down.process(_frame));
    }
    return probability;
  }

  void reset() {
    denoiser.reset();
    _up.reset();
    _down.reset();
    _pending.clear();
    output.clear();
  }
}
