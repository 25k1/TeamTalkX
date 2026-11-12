import 'dart:convert';
import 'dart:typed_data';

class LineFramer {
  final _buffer = <int>[];

  Iterable<String> addBytes(List<int> bytes) sync* {
    for (final b in bytes) {
      if (b == 0x0A) {
        var end = _buffer.length;
        if (end > 0 && _buffer[end - 1] == 0x0D) end--;
        yield utf8.decode(
          Uint8List.fromList(_buffer.sublist(0, end)),
          allowMalformed: true,
        );
        _buffer.clear();
      } else {
        _buffer.add(b);
      }
    }
  }
}
