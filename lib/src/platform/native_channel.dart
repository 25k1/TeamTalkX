import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../diagnostics/log.dart';

class NativeChannel {
  NativeChannel(String name) : _channel = MethodChannel('$_namespace/$name');

  static const _namespace = 'org.gozaltech.teamtalkx';

  final MethodChannel _channel;

  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<T>(method, arguments);
  }

  Future<List<T>?> invokeList<T>(String method, [Object? arguments]) async {
    if (!isSupported) return null;
    return _channel.invokeListMethod<T>(method, arguments);
  }

  Future<T?> invokeQuiet<T>(String method, [Object? arguments]) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      appLog.d('platform', '${_channel.name}.$method failed: ${e.code}');
      return null;
    } on MissingPluginException {
      appLog.d('platform', '${_channel.name}.$method is not implemented');
      return null;
    }
  }

  void setHandler(Future<dynamic> Function(MethodCall call) handler) {
    if (!isSupported) return;
    _channel.setMethodCallHandler(handler);
  }
}
