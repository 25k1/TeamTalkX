import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import '../security/secrets.dart';
import '../settings/settings_providers.dart';
import 'public_servers_providers.dart';

bool isWebLogin(String username) =>
    username == 'bearware' || username.endsWith('@bearware.dk');

class BearwareAccount {
  const BearwareAccount({required this.username, required this.token});

  final String username;
  final String token;

  bool get isLinked => username.isNotEmpty && token.isNotEmpty;
}

final bearwareAccountProvider =
    NotifierProvider<BearwareAccountNotifier, BearwareAccount>(
      BearwareAccountNotifier.new,
    );

class BearwareAccountNotifier extends Notifier<BearwareAccount> {
  static const _tokenKey = 'bearware_token';

  @override
  BearwareAccount build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final secrets = ref.read(secretStoreProvider);
    var token = secrets.read(_tokenKey) ?? '';
    final legacy = prefs.getString(_tokenKey);
    if (legacy != null) {
      if (token.isEmpty) token = legacy;
      unawaited(
        secrets.write(_tokenKey, token).then((_) => prefs.remove(_tokenKey)),
      );
    }
    return BearwareAccount(
      username: prefs.getString('bearware_username') ?? '',
      token: token,
    );
  }

  void save(BearwareAccount account) {
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(prefs.setString('bearware_username', account.username));
    unawaited(ref.read(secretStoreProvider).write(_tokenKey, account.token));
    state = account;
  }

  void reset() => save(const BearwareAccount(username: '', token: ''));
}

class BearwareLoginResult {
  const BearwareLoginResult({
    required this.username,
    required this.nickname,
    required this.token,
  });

  final String username;
  final String nickname;
  final String token;
}

Future<String> _fetchXml(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Web login service returned ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

String _xmlValue(String xml, String element) {
  try {
    return XmlDocument.parse(
          xml,
        ).findAllElements(element).firstOrNull?.innerText ??
        '';
  } on XmlException {
    return '';
  }
}

Future<BearwareLoginResult?> authenticateBearware(
  String username,
  String password,
) async {
  final uri = Uri.https('www.bearware.dk', '/teamtalk/weblogin.php', {
    ...bearwareUrlArgs(),
    'service': 'bearware',
    'action': 'auth',
    'username': username,
    'password': password,
  });
  final xml = await _fetchXml(uri);
  final token = _xmlValue(xml, 'token');
  if (token.isEmpty) return null;
  return BearwareLoginResult(
    username: _xmlValue(xml, 'username'),
    nickname: _xmlValue(xml, 'nickname'),
    token: token,
  );
}

Future<String> resolveWebLoginUsername(
  BearwareAccount account,
  String serverAccessToken,
) async {
  final uri = Uri.https('www.bearware.dk', '/teamtalk/weblogin.php', {
    ...bearwareUrlArgs(),
    'service': 'bearware',
    'action': 'clientauth',
    'username': account.username,
    'token': account.token,
    'accesstoken': serverAccessToken,
  });
  try {
    final xml = await _fetchXml(uri);
    final resolved = _xmlValue(xml, 'username');
    return resolved.isEmpty ? account.username : resolved;
  } on Exception {
    return account.username;
  }
}
