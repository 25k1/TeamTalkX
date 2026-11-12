import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/packet.dart';
import 'package:teamtalkx/src/protocol/voice_crypt.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

final _key = Uint8List.fromList(List.generate(32, (i) => i));

Uint8List _packet({int kind = packetKindVoice}) {
  final p = voicePacket(
    srcUserId: 5,
    channelId: 1,
    streamId: 2,
    packetNumber: 300,
    time: 0x01020304,
    encodedAudio: Uint8List.fromList(List.generate(40, (i) => i)),
  );
  p[0] = kind;
  return p;
}

void main() {
  test('CRC-32 is the standard one (ACE::crc32)', () {
    expect(crc32(ascii.encode('123456789')), 0xCBF43926);
  });

  test('cryptkey hex parses to 32 bytes, anything else is refused', () {
    expect(parseVoiceCryptKey(_hex32()), _key);
    expect(parseVoiceCryptKey(_hex32().toUpperCase()), _key);
    expect(parseVoiceCryptKey(''), isNull);
    expect(parseVoiceCryptKey('00' * 31), isNull);
    expect(parseVoiceCryptKey('zz${'00' * 31}'), isNull);
  });

  test('channel keys follow the channel commands', () {
    final keys = ChannelCryptKeys();
    final other = 'ff' * 32;
    for (final line in [
      'addchannel chanid=1 channel="/" cryptkey="${_hex32()}"',
      'addchannel chanid=2 channel="/Room/" name="Room"',
      'joined chanid=2 cryptkey="$other"',
      'addchannel chanid=3 channel="/Bad/" cryptkey="abc"',
    ]) {
      keys.onCommand(TtCommand.parse(line));
    }
    expect(keys[1], _key);
    expect(keys[2], everyElement(0xFF));
    expect(keys[3], isNull, reason: 'not a 32-byte key');

    keys.onCommand(TtCommand.parse('removechannel chanid=1'));
    expect(keys[1], isNull);
    keys.clear();
    expect(keys[2], isNull);
  });

  group('encrypted packets', () {
    test('match OpenSSL AES-256-CBC with a zero IV, as TeamTalkLib', () {
      final crypt = encryptVoicePacket(_packet(), _key);

      expect(crypt.sublist(0, 8), [4, 5, 0x10, 0, 4, 3, 2, 1]);
      expect(crypt.sublist(8, 10), [64, 0x10]);
      expect(
        crypt.sublist(10),
        _hex(
          '71550308a956df8a5c9dca1b855fb2efe84d89a1815f169e1590b6ef34b19ae4'
          '40710de20668bc36e00fd360daa9db615bc12b241a48d1d9e1b45a70e9926267',
        ),
      );
    });

    test('decrypt back to the plain packet', () {
      for (final kind in [packetKindVoice, packetKindMediaFileAudio]) {
        final plain = _packet(kind: kind);
        final crypt = encryptVoicePacket(plain, _key);
        expect(crypt[0], kind + 1);

        final back = decryptVoicePacket(crypt, _key);

        expect(back, plain);
        final voice = parseVoicePacket(back!)!;
        expect(voice.kind, kind);
        expect(voice.packetNumber, 300);
        expect(voice.encodedAudio, hasLength(40));
      }
    });

    test('fragments encrypt and decrypt one by one', () {
      final fragments = fragmentVoicePacket(
        srcUserId: 5,
        channelId: 1,
        streamId: 2,
        packetNumber: 7,
        time: 0,
        encodedAudio: Uint8List(3000),
      );
      expect(fragments.length, greaterThan(1));
      final assembler = VoiceFragmentAssembler();
      VoicePacket? whole;
      for (final f in fragments) {
        final back = decryptVoicePacket(encryptVoicePacket(f, _key), _key)!;
        whole = assembler.add(parseVoicePacket(back)!) ?? whole;
      }
      expect(whole?.encodedAudio, hasLength(3000));
    });

    test('a wrong key, damage or a plain packet gives nothing', () {
      final crypt = encryptVoicePacket(_packet(), _key);
      final otherKey = Uint8List(32)..fillRange(0, 32, 7);
      expect(decryptVoicePacket(crypt, otherKey), isNull);

      for (var i = 10; i < crypt.length; i++) {
        final damaged = Uint8List.fromList(crypt)..[i] ^= 0x01;
        expect(decryptVoicePacket(damaged, _key), isNull, reason: 'byte $i');
      }
      expect(decryptVoicePacket(crypt.sublist(0, 30), _key), isNull);
      expect(decryptVoicePacket(_packet(), _key), isNull);
      expect(decryptVoicePacket(Uint8List(0), _key), isNull);
    });
  });
}

String _hex32() =>
    [for (final b in _key) b.toRadixString(16).padLeft(2, '0')].join();
