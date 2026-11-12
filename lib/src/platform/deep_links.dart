import 'dart:async';

import 'native_channel.dart';

abstract interface class DeepLinks {
  Stream<String> get links;

  Stream<String> get files;

  Future<String?> getInitialLink();

  Future<String?> getInitialFile();
}

class AndroidDeepLinks implements DeepLinks {
  AndroidDeepLinks() {
    _channel.setHandler((call) async {
      if (call.arguments is! String) return;
      switch (call.method) {
        case 'onLink':
          _links.add(call.arguments as String);
        case 'onFile':
          _files.add(call.arguments as String);
      }
    });
  }

  final _channel = NativeChannel('deeplink');
  final _links = StreamController<String>.broadcast();
  final _files = StreamController<String>.broadcast();

  @override
  Stream<String> get links => _links.stream;

  @override
  Stream<String> get files => _files.stream;

  @override
  Future<String?> getInitialLink() => _channel.invoke<String>('getInitialLink');

  @override
  Future<String?> getInitialFile() => _channel.invoke<String>('getInitialFile');
}
