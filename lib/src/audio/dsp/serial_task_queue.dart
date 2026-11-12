import 'dart:async';
import 'dart:collection';

import '../../diagnostics/log.dart';

class SerialTaskQueue {
  SerialTaskQueue({this.maxQueued = 5});

  final int maxQueued;

  final Queue<_Task<dynamic>> _tasks = Queue<_Task<dynamic>>();
  bool _busy = false;
  Future<void> _idle = Future<void>.value();

  int get length => _tasks.length;

  bool get isBusy => _busy;

  Future<T?> run<T>(Future<T?> Function() action) {
    final task = _Task<T>(action);
    _tasks.addLast(task);
    while (_tasks.length > maxQueued) {
      _tasks.removeFirst().drop();
    }
    _drain();
    return task.future;
  }

  Future<void> close() async {
    while (_tasks.isNotEmpty) {
      _tasks.removeFirst().drop();
    }
    await _idle;
  }

  void _drain() {
    if (_busy) return;
    _busy = true;
    _idle = _drainLoop();
  }

  Future<void> _drainLoop() async {
    try {
      while (_tasks.isNotEmpty) {
        final task = _tasks.removeFirst();
        await task.run();
      }
    } finally {
      _busy = false;
    }
  }
}

class _Task<T> {
  _Task(this._action);

  final Future<T?> Function() _action;
  final Completer<T?> _completer = Completer<T?>();
  bool _finished = false;

  Future<T?> get future => _completer.future;

  void drop() {
    if (_finished) return;
    _finished = true;
    _completer.complete(null);
  }

  Future<void> run() async {
    if (_finished) return;
    _finished = true;
    try {
      _completer.complete(await _action());
    } on Object catch (e, st) {
      appLog.w('queue', 'Queued task failed', e, st);
      _completer.complete(null);
    }
  }
}
