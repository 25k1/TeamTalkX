import 'dart:async';

import 'native_channel.dart';

abstract interface class Connectivity {
  Future<bool> isOnline();

  Stream<bool> get changes;
}

class AndroidConnectivity implements Connectivity {
  AndroidConnectivity() {
    _channel.setHandler((call) async {
      if (call.method == 'changed') _changes.add(call.arguments as bool);
    });
  }

  final _channel = NativeChannel('connectivity');
  final _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async =>
      await _channel.invokeQuiet<bool>('isOnline') ?? true;

  @override
  Stream<bool> get changes => _changes.stream;
}
