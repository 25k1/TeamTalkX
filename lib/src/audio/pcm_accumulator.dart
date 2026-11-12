import 'dart:typed_data';

Int16List pcm16View(Uint8List bytes) {
  final count = bytes.lengthInBytes ~/ 2;
  if (count == 0) return Int16List(0);
  if (bytes.offsetInBytes % 2 == 0) {
    return bytes.buffer.asInt16List(bytes.offsetInBytes, count);
  }
  final out = Int16List(count);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < count; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little);
  }
  return out;
}

class PcmAccumulator {
  PcmAccumulator([int initialCapacity = 4096])
    : _data = Int16List(initialCapacity < 16 ? 16 : initialCapacity),
      _length = 0;

  Int16List _data;
  int _length;

  int get length => _length;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  Int16List get samples => Int16List.sublistView(_data, 0, _length);

  void add(int sample) {
    if (_length == _data.length) _grow(1);
    _data[_length++] = sample;
  }

  void addAll(Int16List source) {
    if (source.isEmpty) return;
    if (_length + source.length > _data.length) _grow(source.length);
    _data.setRange(_length, _length + source.length, source);
    _length += source.length;
  }

  void clear() => _length = 0;

  Int16List peek(int n) {
    assert(n <= _length);
    return Int16List.sublistView(_data, 0, n);
  }

  void consume(int n) {
    assert(n <= _length);
    if (n <= 0) return;
    _length -= n;
    if (_length > 0) {
      _data.setRange(0, _length, _data, n);
    }
  }

  void _grow(int extra) {
    var cap = _data.length;
    while (cap < _length + extra) {
      cap *= 2;
    }
    final next = Int16List(cap);
    next.setRange(0, _length, _data);
    _data = next;
  }
}
