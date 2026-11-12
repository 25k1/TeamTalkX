import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/playout_buffer.dart';

Int16List _decode(int tag) => Int16List(1920)..fillRange(0, 1920, tag);

Int16List _plc(int? next, int packetsAhead, int samplesPerChannel) =>
    Int16List(samplesPerChannel * 2)..fillRange(0, samplesPerChannel * 2, -1);

PlayoutBuffer<int> _buffer() => PlayoutBuffer<int>(decode: _decode, plc: _plc);

List<int> _tags(Int16List? pcm) => [
  if (pcm != null)
    for (var i = 0; i < pcm.length; i += 1920) pcm[i],
];

int _ms(int ms) => ms * 1000;

void main() {
  test('waits for the target, then plays in packet order', () {
    final b = _buffer()..push(1, 1, _ms(0));
    expect(b.pull(_ms(5), 0), isNull, reason: '40 ms not buffered yet');

    b.push(0, 0, _ms(10));
    final out = b.pull(_ms(11), 0);

    expect(b.playing, isTrue);
    expect(_tags(out), [0, 1]);
  });

  test('tops up only what the device needs', () {
    final b = _buffer();
    for (var i = 0; i < 5; i++) {
      b.push(i, i, _ms(i * 20));
    }
    expect(_tags(b.pull(_ms(80), 0)), [0, 1]);
    expect(b.pull(_ms(90), 35), isNull, reason: 'enough queued');
    expect(_tags(b.pull(_ms(100), 10)), [2]);
  });

  test('a missing packet is concealed once a later one arrives', () {
    final b = _buffer()
      ..push(0, 0, _ms(0))
      ..push(2, 2, _ms(40))
      ..push(3, 3, _ms(60));

    final out = b.pull(_ms(60), 0);

    expect(_tags(out), [0, -1]);
    expect(b.concealed, 1);
    expect(_tags(b.pull(_ms(80), 0)), [2, 3]);
  });

  test('a late packet is dropped and raises the target', () {
    final b = PlayoutBuffer<int>(decode: _decode, plc: _plc, minTargetMs: 0)
      ..push(0, 0, _ms(0))
      ..push(2, 2, _ms(40));
    b.pull(_ms(60), 0);
    final before = b.targetMs;

    b.push(1, 1, _ms(70));

    expect(b.late, 1);
    expect(b.targetMs, greaterThan(before));
  });

  test('irregular arrival raises the target, up to 400 ms', () {
    final steady = _buffer();
    final jittery = _buffer();
    for (var i = 0; i < 50; i++) {
      steady.push(i, i, _ms(i * 20));
      jittery.push(i, i, _ms((i ~/ 10) * 200));
    }
    expect(steady.targetMs, 40, reason: 'the 40 ms floor');
    expect(jittery.targetMs, greaterThan(100));

    final extreme = _buffer();
    for (var i = 0; i < 50; i++) {
      extreme.push(i, i, _ms(i.isEven ? i * 20 : i * 20 + 2000));
    }
    expect(extreme.targetMs, 400, reason: 'the 400 ms ceiling');
  });

  group('catch-up (D125)', () {
    test('speeds up with a backlog, back to normal at the target', () {
      final b = _buffer();
      for (var i = 0; i < 15; i++) {
        b.push(i, i, _ms(0));
      }
      b.pull(_ms(0), 0);
      expect(b.speed, 1.12, reason: 'far above the target');

      var now = 0;
      var next = 15;
      var queued = 0.0;
      while (b.speed > 1 && now < _ms(10000)) {
        now += _ms(10);
        queued = (queued - 10 * b.speed).clamp(0, 1000);
        if (now % _ms(20) == 0) b.push(next, next++, now);
        final out = b.pull(now, queued);
        queued += _tags(out).length * 20;
      }
      expect(b.speed, 1);
      expect(b.pendingMs + queued, lessThanOrEqualTo(b.targetMs + 20));
    });

    test('slows down when about to run dry', () {
      final b = _buffer()
        ..push(0, 0, _ms(0))
        ..push(1, 1, _ms(20))
        ..push(2, 2, _ms(40));
      b.pull(_ms(40), 0);
      b.pull(_ms(50), 0);
      b.pull(_ms(60), 5);
      expect(b.speed, 0.94);
    });
  });

  test('a short talk spurt starts after waiting the target', () {
    final b = _buffer()..push(0, 0, _ms(0));
    expect(b.pull(_ms(20), 0), isNull);
    expect(_tags(b.pull(_ms(45), 0)), [0]);
  });

  test('a long silence ends the talk spurt', () {
    final b = _buffer()
      ..push(0, 0, _ms(0))
      ..push(1, 1, _ms(20))
      ..push(2, 2, _ms(40));
    b.pull(_ms(40), 0);
    b.pull(_ms(60), 0);
    expect(b.playing, isTrue);

    expect(b.pull(_ms(200), 0), isNull);
    expect(b.playing, isFalse);
    expect(b.takeEnded(), isTrue);
    expect(b.takeEnded(), isFalse);
    expect(b.speed, 1);
  });

  test('reordered packets play in number order', () {
    final b = _buffer()
      ..push(1, 1, _ms(0))
      ..push(0, 0, _ms(1))
      ..push(3, 3, _ms(40))
      ..push(2, 2, _ms(41));
    expect(_tags(b.pull(_ms(41), 0)), [0, 1]);
    expect(_tags(b.pull(_ms(60), 0)), [2, 3]);
    expect(b.concealed, 0);
  });

  test('consecutive missing packets are each concealed', () {
    final b = _buffer()
      ..push(0, 0, _ms(0))
      ..push(3, 3, _ms(60));
    expect(_tags(b.pull(_ms(60), 0)), [0, -1]);
    expect(_tags(b.pull(_ms(70), 0)), [-1, 3]);
    expect(b.concealed, 2);
  });

  test('concealment gets the next packet and how far ahead it is', () {
    final asked = <(int?, int)>[];
    final b =
        PlayoutBuffer<int>(
            decode: _decode,
            plc: (next, ahead, samples) {
              asked.add((next, ahead));
              return _plc(next, ahead, samples);
            },
          )
          ..push(0, 0, _ms(0))
          ..push(3, 3, _ms(60));
    b
      ..pull(_ms(60), 0)
      ..pull(_ms(70), 0);
    expect(asked, [(3, 2), (3, 1)]);
  });

  test('a jump in packet numbers is skipped, not concealed', () {
    final b = _buffer()
      ..push(0, 0, _ms(0))
      ..push(1, 1, _ms(20));
    b.pull(_ms(20), 0);
    b
      ..push(1000, 7, _ms(40))
      ..push(1001, 8, _ms(60));
    expect(_tags(b.pull(_ms(60), 0)), [7, 8]);
    expect(b.concealed, 0);
  });

  test('a failing decode drops that frame and is counted', () {
    final b =
        PlayoutBuffer<int>(
            decode: (tag) =>
                tag == 1 ? throw StateError('bad frame') : _decode(tag),
            plc: _plc,
          )
          ..push(0, 0, _ms(0))
          ..push(1, 1, _ms(20))
          ..push(2, 2, _ms(40));
    expect(_tags(b.pull(_ms(40), 0)), [0, 2]);
    expect(b.decodeFailures, 1);
    expect(b.lastFailure, isA<StateError>());
  });

  test('overflow drops the oldest packets', () {
    final b = PlayoutBuffer<int>(decode: _decode, plc: _plc, maxPending: 3);
    for (var i = 0; i < 5; i++) {
      b.push(i, i, _ms(0));
    }
    expect(b.pendingMs, 60);
    expect(_tags(b.pull(_ms(0), 0)), [2, 3]);
  });

  test('reset forgets the stream', () {
    final b = _buffer()
      ..push(0, 0, _ms(0))
      ..push(1, 1, _ms(20))
      ..push(2, 2, _ms(40));
    b.pull(_ms(40), 0);
    b.reset();
    expect(b.playing, isFalse);
    expect(b.pendingMs, 0);
    b
      ..push(500, 5, _ms(100))
      ..push(501, 6, _ms(120));
    expect(_tags(b.pull(_ms(120), 0)), [5, 6]);
  });

  test('packet numbers wrap around', () {
    final b = _buffer()
      ..push(65535, 1, _ms(0))
      ..push(0, 2, _ms(20))
      ..push(1, 3, _ms(40));
    expect(_tags(b.pull(_ms(40), 0)), [1, 2]);
  });
}
