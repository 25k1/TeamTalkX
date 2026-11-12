import 'dart:math' as math;
import 'dart:typed_data';

class PlayoutBuffer<T> {
  PlayoutBuffer({
    required this.decode,
    required this.plc,
    this.channels = 2,
    this.sampleRate = 48000,
    this.minTargetMs = 40,
    this.maxTargetMs = 400,
    this.lowWaterMs = 30,
    this.catchUpSpeed = 1.12,
    this.slowDownSpeed = 0.94,
    this.maxPending = 100,
  });

  final Int16List Function(T packet) decode;
  final Int16List Function(T? next, int packetsAhead, int samplesPerChannel)
  plc;
  final int channels;
  final int sampleRate;
  final double minTargetMs;
  final double maxTargetMs;

  final double lowWaterMs;
  final double catchUpSpeed;
  final double slowDownSpeed;
  final int maxPending;

  final _pending = <int, T>{};
  int? _nextNo;
  bool _playing = false;
  int _spurtStartUs = 0;
  int _lastPacketUs = 0;
  int? _lastArrivalNo;
  int _lastArrivalUs = 0;
  double _jitterMs = 0;
  double _lateBonusMs = 0;
  double _frameMs = 20;
  int _samplesPerChannel = 960;
  double _speed = 1;
  bool _ended = false;
  int? _lastPullUs;

  int concealed = 0;
  int late = 0;
  int decodeFailures = 0;
  Object? lastFailure;

  double catchUpMs = 0;
  double slowDownMs = 0;

  bool get playing => _playing;

  double get speed => _speed;

  double get jitterMs => _jitterMs;

  double get targetMs =>
      (_frameMs + 3 * _jitterMs + _lateBonusMs).clamp(minTargetMs, maxTargetMs);

  double get pendingMs => _pending.length * _frameMs;

  bool takeEnded() {
    final ended = _ended;
    _ended = false;
    return ended;
  }

  void push(int packetNo, T packet, int nowUs) {
    final next = _nextNo;
    if (next != null && _seqLt(packetNo, next)) {
      late++;
      _lateBonusMs = math.min(_lateBonusMs + 10, maxTargetMs);
      return;
    }
    if (_pending.isEmpty && !_playing) _spurtStartUs = nowUs;
    _pending[packetNo] = packet;
    while (_pending.length > maxPending) {
      _pending.remove(_minKey());
    }
    final previous = _lastArrivalNo;
    if (previous != null && _seqLt(previous, packetNo)) {
      final steps = (packetNo - previous) & 0xFFFF;
      final expectedMs = steps * _frameMs;
      final actualMs = (nowUs - _lastArrivalUs) / 1000;
      final d = (actualMs - expectedMs).abs();
      _jitterMs += (d - _jitterMs) / 16;
    }
    if (previous == null || _seqLt(previous, packetNo)) {
      _lastArrivalNo = packetNo;
      _lastArrivalUs = nowUs;
    }
    _lastPacketUs = nowUs;
  }

  Int16List? pull(int nowUs, double queuedMs) {
    _lateBonusMs *= 0.999;
    final last = _lastPullUs;
    _lastPullUs = nowUs;
    if (last != null && _playing) {
      final elapsedMs = (nowUs - last) / 1000;
      if (_speed > 1) catchUpMs += elapsedMs;
      if (_speed < 1) slowDownMs += elapsedMs;
    }
    final target = targetMs;
    if (!_playing) {
      if (_pending.isEmpty) return null;
      final waitedMs = (nowUs - _spurtStartUs) / 1000;
      if (pendingMs < target && waitedMs < target) return null;
      _playing = true;
      _nextNo = _minKey();
    }

    final out = <Int16List>[];
    var queued = queuedMs;
    while (queued < lowWaterMs) {
      final no = _nextNo!;
      final packet = _pending.remove(no);
      if (packet != null) {
        final pcm = _safeDecode(packet);
        _nextNo = (no + 1) & 0xFFFF;
        if (pcm == null || pcm.isEmpty) continue;
        _samplesPerChannel = pcm.length ~/ channels;
        _frameMs = _samplesPerChannel * 1000 / sampleRate;
        out.add(pcm);
        queued += _frameMs;
        continue;
      }
      if (_pending.isNotEmpty) {
        final first = _minKey();
        if (((first - no) & 0xFFFF) * _frameMs > maxTargetMs) {
          _nextNo = first;
          continue;
        }
        final pcm = _safePlc(_pending[first], (first - no) & 0xFFFF);
        _nextNo = (no + 1) & 0xFFFF;
        concealed++;
        _lateBonusMs = math.min(_lateBonusMs + 5, maxTargetMs);
        if (pcm != null) out.add(pcm);
        queued += _frameMs;
        continue;
      }
      if ((nowUs - _lastPacketUs) / 1000 > target + 2 * _frameMs) {
        _playing = false;
        _nextNo = null;
        _ended = true;
        _speed = 1;
      }
      break;
    }

    if (_playing) _speed = _speedFor(pendingMs + queued, target);
    if (out.isEmpty) return null;
    if (out.length == 1) return out.single;
    final total = Int16List(out.fold(0, (n, p) => n + p.length));
    var off = 0;
    for (final part in out) {
      total.setAll(off, part);
      off += part.length;
    }
    return total;
  }

  double _speedFor(double bufferedMs, double target) {
    final high = target + math.max(40, target * 0.5);
    final low = target * 0.5;
    if (bufferedMs > high) return catchUpSpeed;
    if (bufferedMs < low) return slowDownSpeed;
    if (_speed > 1 && bufferedMs <= target) return 1;
    if (_speed < 1 && bufferedMs >= target) return 1;
    return _speed;
  }

  void reset() {
    _pending.clear();
    _nextNo = null;
    _playing = false;
    _lastArrivalNo = null;
    _speed = 1;
    _ended = false;
  }

  Int16List? _safeDecode(T packet) {
    try {
      return decode(packet);
    } on Object catch (e) {
      decodeFailures++;
      lastFailure = e;
      return null;
    }
  }

  Int16List? _safePlc(T? next, int packetsAhead) {
    try {
      return plc(next, packetsAhead, _samplesPerChannel);
    } on Object catch (e) {
      decodeFailures++;
      lastFailure = e;
      return null;
    }
  }

  int _minKey() {
    var min = _pending.keys.first;
    for (final k in _pending.keys) {
      if (_seqLt(k, min)) min = k;
    }
    return min;
  }

  static bool _seqLt(int a, int b) {
    final d = (b - a) & 0xFFFF;
    return d != 0 && d < 0x8000;
  }
}
