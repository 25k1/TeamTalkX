import 'package:flutter/services.dart';

import 'native_channel.dart';

class SecretCipherUnavailable implements Exception {
  const SecretCipherUnavailable();
}

class SecretUndecryptable implements Exception {
  const SecretUndecryptable();
}

abstract interface class SecretCipher {
  Future<String> encrypt(String text);

  Future<String> decrypt(String data);
}

class AndroidSecretCipher implements SecretCipher {
  final _channel = NativeChannel('secrets');

  @override
  Future<String> encrypt(String text) => _call('encrypt', {'text': text});

  @override
  Future<String> decrypt(String data) => _call('decrypt', {'data': data});

  Future<String> _call(String method, Map<String, String> args) async {
    if (!NativeChannel.isSupported) throw const SecretCipherUnavailable();
    try {
      final result = await _channel.invoke<String>(method, args);
      if (result == null) throw const SecretCipherUnavailable();
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'undecryptable') throw const SecretUndecryptable();
      throw const SecretCipherUnavailable();
    } on MissingPluginException {
      throw const SecretCipherUnavailable();
    }
  }
}
