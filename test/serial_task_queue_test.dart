import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/serial_task_queue.dart';
import 'package:teamtalkx/src/diagnostics/log.dart';

void main() {
  group('SerialTaskQueue', () {
    test(
      'a failing task yields null, is logged, and the queue continues',
      () async {
        final sink = MemoryLogSink();
        appLog.addSink(sink);
        addTearDown(() => appLog.removeSink(sink));
        final queue = SerialTaskQueue();

        final failed = queue.run<int>(() async => throw StateError('boom'));
        final next = queue.run(() async => 2);

        expect(await failed, isNull);
        expect(await next, 2);
        final record = sink.records.single;
        expect(record.level, LogLevel.warning);
        expect(record.tag, 'queue');
        expect(record.error, contains('boom'));
      },
    );

    test('tasks run sequentially in call order', () async {
      final queue = SerialTaskQueue();
      final order = <int>[];
      final futures = [
        queue.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          order.add(1);
          return 1;
        }),
        queue.run(() async {
          order.add(2);
          return 2;
        }),
        queue.run(() async {
          order.add(3);
          return 3;
        }),
      ];
      final results = await Future.wait(futures);
      expect(order, [1, 2, 3]);
      expect(results, [1, 2, 3]);
    });

    test('queue overflow drops the oldest tasks', () async {
      final queue = SerialTaskQueue(maxQueued: 2);
      final gate = Completer<void>();
      final first = queue.run(() async {
        await gate.future;
        return 1;
      });
      final dropped = queue.run(() async => 2);
      final keptA = queue.run(() async => 3);
      final keptB = queue.run(() async => 4);
      expect(await dropped, isNull);
      gate.complete();
      expect(await first, 1);
      expect(await keptA, 3);
      expect(await keptB, 4);
    });

    test(
      'a throwing task completes with null and does not break the queue',
      () async {
        final queue = SerialTaskQueue();
        final bad = queue.run(() async => throw StateError('boom'));
        final good = queue.run(() async => 42);
        expect(await bad, isNull);
        expect(await good, 42);
      },
    );

    test('close waits for the running task and drops the rest', () async {
      final queue = SerialTaskQueue(maxQueued: 10);
      final gate = Completer<void>();
      var firstRan = false;
      final first = queue.run(() async {
        await gate.future;
        firstRan = true;
        return 1;
      });
      final pending = queue.run(() async => 2);
      final closing = queue.close();
      gate.complete();
      await closing;
      expect(firstRan, isTrue);
      expect(await first, 1);
      expect(await pending, isNull);
    });

    test('length reflects the number of waiting tasks', () async {
      final queue = SerialTaskQueue(maxQueued: 10);
      final gate = Completer<void>();
      unawaited(
        queue.run<int>(() async {
          await gate.future;
          return 0;
        }),
      );
      unawaited(queue.run(() async => 1));
      unawaited(queue.run(() async => 2));
      expect(queue.length, 2);
      expect(queue.isBusy, isTrue);
      gate.complete();
      await queue.close();
      expect(queue.length, 0);
    });
  });
}
