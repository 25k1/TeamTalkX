class OutputIdle {
  OutputIdle({this.idleUs = defaultIdleUs});

  static const defaultIdleUs = 10 * Duration.microsecondsPerSecond;

  final int idleUs;

  bool get isOpen => _open;
  bool _open = false;

  int _lastUs = 0;

  bool needsOpen(int nowUs) {
    _lastUs = nowUs;
    return !_open;
  }

  void opened(int nowUs) {
    _open = true;
    _lastUs = nowUs;
  }

  bool shouldClose(int nowUs, {required bool busy}) {
    if (!_open) return false;
    if (busy) {
      _lastUs = nowUs;
      return false;
    }
    return nowUs - _lastUs >= idleUs;
  }

  void closed() => _open = false;
}
