import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/output_idle.dart';

const _s = Duration.microsecondsPerSecond;

void main() {
  test('closes after 10 s with nothing written', () {
    final idle = OutputIdle()..opened(0);

    expect(idle.shouldClose(9 * _s, busy: false), isFalse);
    expect(idle.shouldClose(10 * _s, busy: false), isTrue);
    idle.closed();
    expect(idle.isOpen, isFalse);
    expect(idle.shouldClose(20 * _s, busy: false), isFalse);
  });

  test('each write restarts the wait', () {
    final idle = OutputIdle()..opened(0);

    expect(idle.needsOpen(8 * _s), isFalse);
    expect(idle.shouldClose(17 * _s, busy: false), isFalse);
    expect(idle.shouldClose(18 * _s, busy: false), isTrue);
  });

  test('audio still queued keeps it open and restarts the wait', () {
    final idle = OutputIdle()..opened(0);

    expect(idle.shouldClose(30 * _s, busy: true), isFalse);
    expect(idle.shouldClose(39 * _s, busy: false), isFalse);
    expect(idle.shouldClose(40 * _s, busy: false), isTrue);
  });

  test('a write to a closed output asks for it to open', () {
    final idle = OutputIdle()..opened(0);
    expect(idle.shouldClose(10 * _s, busy: false), isTrue);
    idle.closed();

    expect(idle.needsOpen(12 * _s), isTrue);
    idle.opened(12 * _s);
    expect(idle.needsOpen(12 * _s), isFalse);
    expect(idle.shouldClose(21 * _s, busy: false), isFalse);
  });
}
