import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/protocol/long_text.dart';

TtTextMessage _part(
  String text, {
  bool more = false,
  int from = 3,
  TtMsgType type = TtMsgType.channel,
}) => TtTextMessage(
  type: type,
  fromUserId: from,
  fromUsername: '',
  toUserId: 0,
  channelId: 1,
  text: text,
  more: more,
);

void main() {
  test('short text is one part', () {
    expect(splitText('hello'), ['hello']);
    expect(splitText('a' * 511), hasLength(1));
  });

  test('long text splits into parts of at most 511 bytes', () {
    final text = 'a' * 1200;
    final parts = splitText(text);
    expect(parts.map((p) => p.length), [511, 511, 178]);
    expect(parts.join(), text);
  });

  test('never inside a character', () {
    final text = 'ქართული 😀 ' * 60;
    final parts = splitText(text);
    expect(parts.length, greaterThan(1));
    for (final part in parts) {
      final bytes = utf8.encode(part);
      expect(bytes.length, lessThanOrEqualTo(511));
      expect(utf8.decode(bytes), part, reason: 'whole characters only');
    }
    expect(parts.join(), text);
  });

  group('TextReassembler', () {
    test('a single message passes through', () {
      final whole = TextReassembler().add(_part('hi'));
      expect(whole?.text, 'hi');
    });

    test('parts join until one without more', () {
      final r = TextReassembler();
      expect(r.add(_part('Hello, ', more: true)), isNull);
      expect(r.add(_part('wor', more: true)), isNull);
      final whole = r.add(_part('ld'));
      expect(whole?.text, 'Hello, world');
      expect(whole?.more, isFalse);
    });

    test('senders and types are kept apart', () {
      final r = TextReassembler();
      r.add(_part('A1', more: true));
      r.add(_part('B1', more: true, from: 4));
      r.add(_part('P1', more: true, type: TtMsgType.user));
      expect(r.add(_part('B2', from: 4))?.text, 'B1B2');
      expect(r.add(_part('A2'))?.text, 'A1A2');
      expect(r.add(_part('P2', type: TtMsgType.user))?.text, 'P1P2');
    });

    test('a sender who never finishes is dropped', () {
      final r = TextReassembler();
      for (var i = 0; i < TextReassembler.maxParts; i++) {
        r.add(_part('x', more: true));
      }
      expect(r.add(_part('x', more: true)), isNull);
      expect(r.add(_part('end'))?.text, 'end', reason: 'started over');
    });
  });
}
