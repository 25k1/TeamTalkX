import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/protocol/line_framer.dart';

void main() {
  List<String> feed(LineFramer framer, String text) =>
      framer.addBytes(utf8.encode(text)).toList();

  test('single CRLF line', () {
    expect(feed(LineFramer(), 'pong\r\n'), ['pong']);
  });

  test('line split across chunks', () {
    final framer = LineFramer();
    expect(feed(framer, 'teamt'), isEmpty);
    expect(feed(framer, 'alk protocol="5.14"\r\n'), [
      'teamtalk protocol="5.14"',
    ]);
  });

  test('multiple lines in one chunk', () {
    expect(
      feed(LineFramer(), 'begin id=1\r\naddchannel chanid=1\r\nend id=1\r\n'),
      ['begin id=1', 'addchannel chanid=1', 'end id=1'],
    );
  });

  test('accepts bare LF and strips CR', () {
    expect(feed(LineFramer(), 'a\nb\r\n'), ['a', 'b']);
  });

  test('decodes UTF-8 split across a chunk boundary', () {
    final framer = LineFramer();
    final bytes = utf8.encode('nick="Bjørn"\r\n');
    final cut = bytes.indexOf(0xC3) + 1;
    expect(framer.addBytes(bytes.sublist(0, cut)).toList(), isEmpty);
    expect(framer.addBytes(bytes.sublist(cut)).toList(), ['nick="Bjørn"']);
  });
}
