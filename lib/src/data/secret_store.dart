import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/log.dart';
import '../platform/secret_cipher.dart';

class SecretStore {
  SecretStore._(this._file, this._cipher, this._values);

  SecretStore.memory() : this._(null, null, {});

  static const _version = 1;

  final File? _file;
  final SecretCipher? _cipher;
  final Map<String, String> _values;
  Future<void> _writes = Future.value();
  bool _warnedPlain = false;

  bool? get encrypted => _encrypted;
  bool? _encrypted;

  static Future<SecretStore> open(File file, SecretCipher cipher) async {
    final values = <String, String>{};
    bool? encrypted;
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json case {'keystore': final String data}) {
          final plain = await cipher.decrypt(data);
          values.addAll((jsonDecode(plain) as Map).cast<String, String>());
          encrypted = true;
        } else if (json case {'plain': final Map<Object?, Object?> plain}) {
          values.addAll(plain.cast<String, String>());
          encrypted = false;
        }
      } on SecretUndecryptable {
        appLog.w(
          'secrets',
          'Saved secrets are from another key; starting over',
        );
        await _delete(file);
      } on SecretCipherUnavailable {
        appLog.w('secrets', 'The Keystore is unavailable; secrets not loaded');
      } on FormatException catch (e) {
        appLog.w('secrets', 'The secrets file is damaged; starting over', e);
        await _delete(file);
      } on TypeError catch (e) {
        appLog.w('secrets', 'The secrets file is damaged; starting over', e);
        await _delete(file);
      }
    }
    return SecretStore._(file, cipher, values).._encrypted = encrypted;
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException catch (_) {}
  }

  String? read(String key) => _values[key];

  Future<void> flush() => _writes;

  Future<void> write(String key, String? value) => writeAll({key: value});

  Future<void> writeAll(Map<String, String?> changes) {
    for (final MapEntry(:key, :value) in changes.entries) {
      if (value == null || value.isEmpty) {
        _values.remove(key);
      } else {
        _values[key] = value;
      }
    }
    final snapshot = Map<String, String>.of(_values);
    return _writes = _writes
        .then((_) => _save(snapshot))
        .onError<Object>(
          (e, st) => appLog.w('secrets', 'Saving secrets failed', e, st),
        );
  }

  Future<void> _save(Map<String, String> values) async {
    final file = _file;
    final cipher = _cipher;
    if (file == null || cipher == null) return;
    try {
      if (values.isEmpty) return await _delete(file);
      Map<String, Object> content;
      try {
        content = {
          'version': _version,
          'keystore': await cipher.encrypt(jsonEncode(values)),
        };
        _encrypted = true;
      } on SecretCipherUnavailable {
        if (!_warnedPlain) {
          _warnedPlain = true;
          appLog.w(
            'secrets',
            'The Keystore is unavailable; saving secrets unencrypted, '
                'excluded from backup',
          );
        }
        content = {'version': _version, 'plain': values};
        _encrypted = false;
      }
      await _writeFile(file, content);
    } on FileSystemException catch (e) {
      appLog.w('secrets', 'Saving secrets failed', e);
    }
  }

  Future<void> _writeFile(File file, Map<String, Object> content) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(content), flush: true);
    await temp.rename(file.path);
  }
}
