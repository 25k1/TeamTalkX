import 'dart:typed_data';

const int vadSampleRate = 16000;

Uint8List resampleForVad(
  Uint8List pcm, {
  required int sampleRate,
  required int channels,
}) {
  final mono = _toMono(pcm, channels);
  if (sampleRate == vadSampleRate) return _toBytes(mono);
  if (mono.isEmpty) return Uint8List(0);

  if (sampleRate > vadSampleRate && sampleRate % vadSampleRate == 0) {
    return _toBytes(_decimateAveraging(mono, sampleRate ~/ vadSampleRate));
  }
  return _toBytes(_resampleLinear(mono, sampleRate, vadSampleRate));
}

Int16List _toMono(Uint8List pcm, int channels) {
  final samples = pcm.lengthInBytes ~/ 2;
  if (samples == 0) return Int16List(0);
  final bytes = ByteData.sublistView(pcm);
  if (channels <= 1) {
    final out = Int16List(samples);
    for (var i = 0; i < samples; i++) {
      out[i] = bytes.getInt16(i * 2, Endian.little);
    }
    return out;
  }
  final frames = samples ~/ channels;
  final out = Int16List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += bytes.getInt16((f * channels + c) * 2, Endian.little);
    }
    out[f] = (sum / channels).round();
  }
  return out;
}

Int16List _decimateAveraging(Int16List input, int factor) {
  final out = Int16List(input.length ~/ factor);
  for (var i = 0; i < out.length; i++) {
    var sum = 0;
    for (var j = 0; j < factor; j++) {
      sum += input[i * factor + j];
    }
    out[i] = (sum / factor).round();
  }
  return out;
}

Int16List _resampleLinear(Int16List input, int fromRate, int toRate) {
  if (input.length < 2) return Int16List(0);
  final count = (input.length * toRate) ~/ fromRate;
  final out = Int16List(count);
  final step = fromRate / toRate;
  for (var i = 0; i < count; i++) {
    final pos = i * step;
    final left = pos.floor();
    final right = left + 1;
    if (right >= input.length) {
      out[i] = input[input.length - 1];
      continue;
    }
    final t = pos - left;
    out[i] = (input[left] * (1 - t) + input[right] * t).round();
  }
  return out;
}

Uint8List _toBytes(Int16List samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return out;
}

class StreamingResampler {
  StreamingResampler(this.fromRate, this.toRate);

  final int fromRate;
  final int toRate;

  int _position = 0;
  int _previous = 0;

  Int16List process(Int16List input) {
    if (fromRate == toRate) return input;
    if (input.isEmpty) return Int16List(0);
    final last = input.length;
    int at(int i) => i == 0 ? _previous : input[i - 1];
    final out = <int>[];
    final end = last * toRate;
    while (_position < end) {
      final i = _position ~/ toRate;
      final fraction = (_position % toRate) / toRate;
      final a = at(i);
      out.add((a + (at(i + 1) - a) * fraction).round().clamp(-32768, 32767));
      _position += fromRate;
    }
    _position -= end;
    _previous = input.last;
    return Int16List.fromList(out);
  }

  void reset() {
    _position = 0;
    _previous = 0;
  }
}

Int16List resamplePcm(
  Int16List pcm,
  int inRate,
  int inChannels,
  int outRate,
  int outChannels,
) {
  final Int16List mid;
  if (inChannels == outChannels) {
    mid = pcm;
  } else if (inChannels == 2 && outChannels == 1) {
    mid = Int16List(pcm.length ~/ 2);
    for (var i = 0; i < mid.length; i++) {
      mid[i] = (pcm[i * 2] + pcm[i * 2 + 1]) ~/ 2;
    }
  } else if (inChannels == 1 && outChannels == 2) {
    mid = Int16List(pcm.length * 2);
    for (var i = 0; i < pcm.length; i++) {
      mid[i * 2] = pcm[i];
      mid[i * 2 + 1] = pcm[i];
    }
  } else {
    mid = pcm;
  }

  if (inRate == outRate) return mid;
  final inFrames = mid.length ~/ outChannels;
  if (inRate > outRate && inRate % outRate == 0) {
    final factor = inRate ~/ outRate;
    final outFrames = inFrames ~/ factor;
    final out = Int16List(outFrames * outChannels);
    for (var i = 0; i < outFrames; i++) {
      for (var ch = 0; ch < outChannels; ch++) {
        var sum = 0;
        for (var k = 0; k < factor; k++) {
          sum += mid[(i * factor + k) * outChannels + ch];
        }
        out[i * outChannels + ch] = (sum / factor).round();
      }
    }
    return out;
  }
  final outFrames = (inFrames * outRate / inRate).floor();
  final out = Int16List(outFrames * outChannels);
  final ratio = inRate / outRate;
  for (var i = 0; i < outFrames; i++) {
    final pos = i * ratio;
    final i0 = pos.floor();
    final i1 = i0 + 1 < inFrames ? i0 + 1 : i0;
    final frac = pos - i0;
    for (var ch = 0; ch < outChannels; ch++) {
      final a = mid[i0 * outChannels + ch];
      final bSample = mid[i1 * outChannels + ch];
      out[i * outChannels + ch] = (a + (bSample - a) * frac).round();
    }
  }
  return out;
}
