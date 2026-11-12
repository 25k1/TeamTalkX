import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/secret_store.dart';
import '../../diagnostics/log.dart';
import '../../platform/secret_cipher.dart';

final secretStoreProvider = Provider<SecretStore>(
  (ref) => SecretStore.memory(),
);

const secretsFileName = 'secrets.json';

Future<SecretStore> openSecretStore() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return await SecretStore.open(
      File('${dir.path}${Platform.pathSeparator}$secretsFileName'),
      AndroidSecretCipher(),
    );
  } on Exception catch (e) {
    appLog.w('secrets', 'No secret storage', e);
    return SecretStore.memory();
  }
}
