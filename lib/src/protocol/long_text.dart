import 'dart:convert';

import '../domain/models.dart';

const maxTextPartBytes = 511;

List<String> splitText(String text, {int maxBytes = maxTextPartBytes}) {
  if (utf8.encode(text).length <= maxBytes) return [text];
  final parts = <String>[];
  final part = StringBuffer();
  var bytes = 0;
  for (final rune in text.runes) {
    final size = _utf8Length(rune);
    if (bytes + size > maxBytes) {
      parts.add(part.toString());
      part.clear();
      bytes = 0;
    }
    part.writeCharCode(rune);
    bytes += size;
  }
  if (part.isNotEmpty) parts.add(part.toString());
  return parts;
}

int _utf8Length(int rune) => rune < 0x80
    ? 1
    : rune < 0x800
    ? 2
    : rune < 0x10000
    ? 3
    : 4;

class TextReassembler {
  static const maxParts = 1000;

  final _pending = <(TtMsgType, int), List<TtTextMessage>>{};

  TtTextMessage? add(TtTextMessage part) {
    final key = (part.type, part.fromUserId);
    if (!part.more) {
      final earlier = _pending.remove(key);
      if (earlier == null) return part;
      return TtTextMessage(
        type: part.type,
        fromUserId: part.fromUserId,
        fromUsername: part.fromUsername,
        toUserId: part.toUserId,
        channelId: part.channelId,
        text: [for (final p in earlier) p.text, part.text].join(),
        more: false,
      );
    }
    final parts = _pending.putIfAbsent(key, () => []);
    if (parts.length >= maxParts) {
      _pending.remove(key);
      return null;
    }
    parts.add(part);
    return null;
  }

  void clear() => _pending.clear();
}
