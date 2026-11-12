import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart'
    show AEADParameters, InvalidCipherTextException, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart' show Pbkdf2Parameters;
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

class WrongPassphrase implements Exception {
  const WrongPassphrase();
}

abstract final class PassphraseBox {
  static const iterations = 210000;

  static Future<Map<String, Object>> seal(
    String text,
    String passphrase, {
    int iterations = iterations,
  }) {
    final random = Random.secure();
    Uint8List bytes(int n) =>
        Uint8List.fromList([for (var i = 0; i < n; i++) random.nextInt(256)]);
    final salt = bytes(16);
    final nonce = bytes(12);
    return Isolate.run(() {
      final key = _key(passphrase, salt, iterations);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
        );
      final sealed = cipher.process(Uint8List.fromList(utf8.encode(text)));
      return <String, Object>{
        'kdf': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': base64Encode(salt),
        'cipher': 'aes-256-gcm',
        'nonce': base64Encode(nonce),
        'data': base64Encode(sealed),
      };
    });
  }

  static Future<String> open(
    Map<String, Object?> box,
    String passphrase,
  ) async {
    if (box['kdf'] != 'pbkdf2-hmac-sha256' || box['cipher'] != 'aes-256-gcm') {
      throw const FormatException('Unknown encryption');
    }
    final iterations = box['iterations'];
    final salt = box['salt'];
    final nonce = box['nonce'];
    final data = box['data'];
    if (iterations is! int ||
        iterations < 1 ||
        salt is! String ||
        nonce is! String ||
        data is! String) {
      throw const FormatException('Damaged encryption block');
    }
    final opened = await Isolate.run(() {
      final key = _key(passphrase, base64Decode(salt), iterations);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            128,
            base64Decode(nonce),
            Uint8List(0),
          ),
        );
      try {
        return utf8.decode(cipher.process(base64Decode(data)));
      } on InvalidCipherTextException {
        return null;
      } on ArgumentError {
        return null;
      }
    });
    if (opened == null) throw const WrongPassphrase();
    return opened;
  }

  static Uint8List _key(String passphrase, Uint8List salt, int iterations) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(passphrase)));
  }
}
