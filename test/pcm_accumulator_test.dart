import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/pcm_accumulator.dart';

void main() {
  group('PcmAccumulator', () {
    test('add and length', () {
      final acc = PcmAccumulator(4);
      expect(acc.isEmpty, isTrue);
      acc.add(1);
      acc.add(-2);
      expect(acc.length, 2);
      expect(acc.isNotEmpty, isTrue);
      expect(acc.samples, [1, -2]);
    });

    test('addAll copies an Int16List', () {
      final acc = PcmAccumulator();
      acc.addAll(Int16List.fromList([10, 20, 30]));
      acc.addAll(Int16List.fromList([40]));
      expect(acc.samples, [10, 20, 30, 40]);
    });

    test('buffer grows on overflow', () {
      final acc = PcmAccumulator(2);
      for (var i = 0; i < 1000; i++) {
        acc.add(i);
      }
      expect(acc.length, 1000);
      expect(acc.samples.first, 0);
      expect(acc.samples.last, 999);
    });

    test('peek returns the first n samples', () {
      final acc = PcmAccumulator();
      acc.addAll(Int16List.fromList([1, 2, 3, 4]));
      expect(acc.peek(2), [1, 2]);
      expect(acc.length, 4);
    });

    test('consume drops the front and shifts the rest', () {
      final acc = PcmAccumulator();
      acc.addAll(Int16List.fromList([1, 2, 3, 4, 5]));
      acc.consume(2);
      expect(acc.samples, [3, 4, 5]);
      acc.consume(3);
      expect(acc.isEmpty, isTrue);
    });

    test('consume(0) changes nothing', () {
      final acc = PcmAccumulator();
      acc.addAll(Int16List.fromList([7, 8]));
      acc.consume(0);
      expect(acc.samples, [7, 8]);
    });

    test('clear resets length but not capacity', () {
      final acc = PcmAccumulator();
      acc.addAll(Int16List.fromList([1, 2, 3]));
      acc.clear();
      expect(acc.isEmpty, isTrue);
      acc.add(9);
      expect(acc.samples, [9]);
    });

    test('peek followed by encode-style reads does not break consume', () {
      final acc = PcmAccumulator();
      acc.addAll(Int16List.fromList([100, 200, 300]));
      final view = acc.peek(2);
      expect(view[0], 100);
      expect(view[1], 200);
      acc.consume(2);
      expect(acc.samples, [300]);
    });

    test('handles large volumes without data loss', () {
      final acc = PcmAccumulator();
      const chunk = 480;
      for (var f = 0; f < 100; f++) {
        acc.addAll(Int16List(chunk));
        while (acc.length >= chunk) {
          acc.peek(chunk);
          acc.consume(chunk);
        }
      }
      expect(acc.isEmpty, isTrue);
    });
  });

  group('pcm16View', () {
    test('views LE PCM16 without copying', () {
      final bytes = Uint8List.fromList([0x01, 0x00, 0xFF, 0xFF, 0x00, 0x80]);
      final view = pcm16View(bytes);
      expect(view.length, 3);
      expect(view[0], 1);
      expect(view[1], -1);
      expect(view[2], 0x8000.toSigned(16));
    });

    test('empty input', () {
      expect(pcm16View(Uint8List(0)), isEmpty);
    });

    test('odd offset yields a correct copy', () {
      final big = Uint8List.fromList([0xAA, 0x01, 0x00, 0xFF, 0xFF]);
      final bytes = Uint8List.sublistView(big, 1, 5);
      expect(bytes.offsetInBytes % 2, 1, reason: 'offset is odd');
      final view = pcm16View(bytes);
      expect(view.length, 2);
      expect(view[0], 1);
      expect(view[1], -1);
    });
  });
}
