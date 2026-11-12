import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

void main() {
  test('HELLO packet has the exact wire bytes', () {
    final hello = helloPacket(3722, 0x12345678);
    expect(hello, [
      0x01,
      0x8A,
      0x0E,
      0x00,
      0x78,
      0x56,
      0x34,
      0x12,
      0x01,
      0x10,
      0x01,
    ]);
  });

  test('header round-trips through parseHeader', () {
    final hello = helloPacket(3722, 0x12345678);
    final h = parseHeader(hello);
    expect(h.kind, packetKindHello);
    expect(h.srcUserId, 3722);
    expect(h.destChannelId, 0);
    expect(h.time, 0x12345678);
    expect(h.headerSize, 8);
  });

  test('12-bit user id near the max round-trips', () {
    final h = parseHeader(keepAlivePacket(4095, 999));
    expect(h.kind, packetKindKeepAlive);
    expect(h.srcUserId, 4095);
    expect(h.time, 999);
  });

  test('built voice packet round-trips through parseVoicePacket', () {
    final enc = Uint8List.fromList([0x11, 0x22, 0x33, 0x44]);
    final pkt = voicePacket(
      srcUserId: 3722,
      channelId: 5,
      streamId: 9,
      packetNumber: 4242,
      time: 0x0A0B0C0D,
      encodedAudio: enc,
    );
    final h = parseHeader(pkt);
    expect(h.kind, packetKindVoice);
    expect(h.srcUserId, 3722);
    expect(h.destChannelId, 5);
    expect(h.time, 0x0A0B0C0D);

    final v = parseVoicePacket(pkt)!;
    expect(v.srcUserId, 3722);
    expect(v.channelId, 5);
    expect(v.streamId, 9);
    expect(v.packetNumber, 4242);
    expect(v.encodedAudio, enc);
  });

  test('voice packet round-trips frame sizes (even count)', () {
    final enc = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    final pkt = voicePacket(
      srcUserId: 1,
      channelId: 2,
      streamId: 3,
      packetNumber: 4,
      time: 5,
      encodedAudio: enc,
      frameSizes: [2, 3, 1, 4],
    );
    final v = parseVoicePacket(pkt)!;
    expect(v.frameSizes, [2, 3, 1, 4]);
    expect(v.encodedAudio, enc);
    expect(v.encodedAudio.length, v.frameSizes.fold<int>(0, (a, b) => a + b));
  });

  test('voice packet round-trips frame sizes (odd count)', () {
    final enc = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final pkt = voicePacket(
      srcUserId: 1,
      channelId: 2,
      streamId: 3,
      packetNumber: 4,
      time: 5,
      encodedAudio: enc,
      frameSizes: [2, 3, 1],
    );
    final v = parseVoicePacket(pkt)!;
    expect(v.frameSizes, [2, 3, 1]);
  });

  test('voice packet without frame sizes keeps them empty', () {
    final pkt = voicePacket(
      srcUserId: 1,
      channelId: 2,
      streamId: 3,
      packetNumber: 4,
      time: 5,
      encodedAudio: Uint8List.fromList([9, 8, 7]),
    );
    final v = parseVoicePacket(pkt)!;
    expect(v.frameSizes, isEmpty);
    expect(v.encodedAudio, [9, 8, 7]);
  });

  test('frame sizes survive 12-bit values up to 4095', () {
    final sizes = [4095, 1, 2048, 12, 4095];
    final enc = Uint8List(4095 + 1 + 2048 + 12 + 4095);
    final pkt = voicePacket(
      srcUserId: 1,
      channelId: 2,
      streamId: 3,
      packetNumber: 4,
      time: 5,
      encodedAudio: enc,
      frameSizes: sizes,
    );
    final v = parseVoicePacket(pkt)!;
    expect(v.frameSizes, sizes);
  });

  test('parses a voice packet into speaker/stream/audio', () {
    final pkt = Uint8List.fromList([
      0x03,
      0x6D,
      0x5E,
      0x00,
      0xE8,
      0x03,
      0x00,
      0x00,
      0x03,
      0x10,
      0x07,
      0x2A,
      0x00,
      0x03,
      0x40,
      0xAA,
      0xBB,
      0xCC,
    ]);
    final v = parseVoicePacket(pkt)!;
    expect(v.srcUserId, 3693);
    expect(v.channelId, 5);
    expect(v.streamId, 7);
    expect(v.packetNumber, 42);
    expect(v.encodedAudio, [0xAA, 0xBB, 0xCC]);
  });

  group('fragments (BuildAudioFragments / ReassembleAudioPacket)', () {
    Uint8List payload(int n) =>
        Uint8List.fromList(List.generate(n, (i) => i & 0xFF));

    test('fragments carry the count on 0 and their number after', () {
      final fragments = fragmentVoicePacket(
        srcUserId: 5,
        channelId: 2,
        streamId: 9,
        packetNumber: 0x0102,
        time: 0,
        encodedAudio: Uint8List.fromList([10, 11, 12, 13, 14]),
        maxChunk: 2,
      );

      expect(fragments, hasLength(3));
      expect(fragments[0].sublist(8), [
        0x02,
        0x40,
        10,
        11,
        0x04,
        0x20,
        9,
        0x02,
        0x01,
        3,
      ]);
      expect(fragments[2].sublist(8), [
        0x01,
        0x40,
        14,
        0x04,
        0x30,
        9,
        0x02,
        0x01,
        2,
      ]);

      final first = parseVoicePacket(fragments[0])!;
      expect(first.fragmentNo, 0);
      expect(first.fragmentCount, 3);
      expect(first.packetNumber, 0x0102);
      final last = parseVoicePacket(fragments[2])!;
      expect(last.fragmentNo, 2);
      expect(last.fragmentCount, isNull);
    });

    test('a packet that fits is not fragmented', () {
      final packets = fragmentVoicePacket(
        srcUserId: 1,
        channelId: 1,
        streamId: 1,
        packetNumber: 1,
        time: 0,
        encodedAudio: payload(1250),
      );
      expect(packets, hasLength(1));
      expect(parseVoicePacket(packets.single)!.isFragment, isFalse);
    });

    test('media-file audio keeps its kind, whole or fragmented', () {
      for (final size in [100, 3000]) {
        final packets = fragmentVoicePacket(
          kind: packetKindMediaFileAudio,
          srcUserId: 1,
          channelId: 1,
          streamId: 1,
          packetNumber: 1,
          time: 0,
          encodedAudio: payload(size),
        );
        for (final p in packets) {
          expect(parseVoicePacket(p)!.kind, packetKindMediaFileAudio);
        }
      }
    });

    test('fragments reassemble in any order', () {
      final audio = payload(3000);
      final fragments = fragmentVoicePacket(
        srcUserId: 3,
        channelId: 1,
        streamId: 4,
        packetNumber: 77,
        time: 0,
        encodedAudio: audio,
        frameSizes: [1000, 1000, 1000],
      ).map((b) => parseVoicePacket(b)!).toList();
      final assembler = VoiceFragmentAssembler();

      expect(assembler.add(fragments[2]), isNull);
      expect(assembler.add(fragments[0]), isNull);
      final whole = assembler.add(fragments[1])!;

      expect(whole.isFragment, isFalse);
      expect(whole.encodedAudio, audio);
      expect(whole.frameSizes, [1000, 1000, 1000]);
      expect(whole.packetNumber, 77);
    });

    test('a set with a missing fragment never completes', () {
      final fragments = fragmentVoicePacket(
        srcUserId: 3,
        channelId: 1,
        streamId: 4,
        packetNumber: 1,
        time: 0,
        encodedAudio: payload(3000),
      ).map((b) => parseVoicePacket(b)!).toList();
      final assembler = VoiceFragmentAssembler();
      expect(assembler.add(fragments[0]), isNull);
      expect(assembler.add(fragments[2]), isNull);
    });

    test('frame sizes that disagree with the audio are rejected', () {
      final fragments = fragmentVoicePacket(
        srcUserId: 3,
        channelId: 1,
        streamId: 4,
        packetNumber: 1,
        time: 0,
        encodedAudio: payload(2600),
        frameSizes: [1000, 1000],
      ).map((b) => parseVoicePacket(b)!).toList();
      final assembler = VoiceFragmentAssembler();
      for (final f in fragments.take(fragments.length - 1)) {
        assembler.add(f);
      }
      expect(assembler.add(fragments.last), isNull);
    });

    test('whole packets pass through, and old sets are dropped', () {
      final assembler = VoiceFragmentAssembler(maxPending: 2);
      final whole = parseVoicePacket(
        voicePacket(
          srcUserId: 1,
          channelId: 1,
          streamId: 1,
          packetNumber: 1,
          time: 0,
          encodedAudio: payload(10),
        ),
      )!;
      expect(assembler.add(whole), same(whole));

      List<VoicePacket> set(int packetNumber) => fragmentVoicePacket(
        srcUserId: 1,
        channelId: 1,
        streamId: 1,
        packetNumber: packetNumber,
        time: 0,
        encodedAudio: payload(20),
        maxChunk: 10,
      ).map((b) => parseVoicePacket(b)!).toList();
      final oldest = set(1);
      assembler
        ..add(oldest[0])
        ..add(set(2)[0])
        ..add(set(3)[0]);
      expect(assembler.add(oldest[1]), isNull);
    });
  });

  group('splitAudioFrames', () {
    final audio = Uint8List.fromList(List.generate(12, (i) => i));

    test('splits by the frame sizes', () {
      final frames = splitAudioFrames(audio, [5, 3, 4])!;
      expect(frames.map((f) => f.toList()), [
        [0, 1, 2, 3, 4],
        [5, 6, 7],
        [8, 9, 10, 11],
      ]);
    });

    test('without sizes, splits into equal frames per packet', () {
      expect(
        splitAudioFrames(audio, const [], framesPerPacket: 3),
        hasLength(3),
      );
      expect(splitAudioFrames(audio, const []), [audio]);
    });

    test('rejects sizes or counts that do not fit', () {
      expect(splitAudioFrames(audio, [5, 5]), isNull);
      expect(splitAudioFrames(audio, const [], framesPerPacket: 5), isNull);
    });
  });
}
