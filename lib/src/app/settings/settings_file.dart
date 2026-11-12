import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/passphrase_box.dart';
import '../../domain/server_entry.dart';
import '../channels/channel_tree_providers.dart';
import '../chat/chat_templates.dart';
import '../files/file_providers.dart';
import '../security/secrets.dart';
import '../servers/bearware_login.dart';
import '../servers/server_list_providers.dart';
import '../users/user_config.dart';
import 'event_config.dart';
import 'settings_providers.dart';
import 'sound_packs.dart';

class SettingsFile {
  const SettingsFile({
    required this.preferences,
    required this.servers,
    this.passwords,
  });

  final Map<String, Object> preferences;
  final List<ServerEntry> servers;

  final Map<String, Object?>? passwords;

  static const format = 'teamtalkx-settings';

  factory SettingsFile.parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map || json['format'] != format) {
      throw const FormatException('Not a TeamTalkX settings file');
    }
    final version = json['version'];
    if (version is! int || version > 1) {
      throw const FormatException('A newer settings file');
    }
    final preferences = <String, Object>{};
    for (final MapEntry(:key, :value)
        in (json['preferences'] as Map? ?? const {}).entries) {
      final decoded = _decodePreference(value);
      if (key is String && decoded != null) preferences[key] = decoded;
    }
    final servers = ServerEntry.decodeList(jsonEncode(json['servers'] ?? []));
    final passwords = json['passwords'];
    return SettingsFile(
      preferences: preferences,
      servers: servers,
      passwords: passwords is Map ? passwords.cast<String, Object?>() : null,
    );
  }

  static Object? _decodePreference(Object? entry) {
    if (entry is! Map) return null;
    final value = entry['value'];
    return switch (entry['type']) {
      'bool' when value is bool => value,
      'int' when value is int => value,
      'double' when value is num => value.toDouble(),
      'string' when value is String => value,
      'strings' when value is List => [for (final v in value) '$v'],
      _ => null,
    };
  }

  static Map<String, Object> _encodePreference(Object value) => switch (value) {
    bool() => {'type': 'bool', 'value': value},
    int() => {'type': 'int', 'value': value},
    double() => {'type': 'double', 'value': value},
    List<String>() => {'type': 'strings', 'value': value},
    _ => {'type': 'string', 'value': '$value'},
  };
}

class SettingsPassphraseWrong implements Exception {
  const SettingsPassphraseWrong();
}

class ImportPreview {
  const ImportPreview({
    required this.settings,
    required this.newServers,
    required this.knownServers,
  });

  final int settings;
  final int newServers;
  final int knownServers;
}

final settingsFileProvider = Provider<SettingsFileService>(
  SettingsFileService.new,
);

class SettingsFileService {
  SettingsFileService(this._ref);

  final Ref _ref;

  static const _notExported = {
    'sound_pack_folder',
    'sound_pack_folder_name',
    'server_list',
    'bearware_token',
  };

  SharedPreferences get _prefs => _ref.read(sharedPreferencesProvider);

  Future<String> export({
    required String appVersion,
    String? passphrase,
    DateTime? now,
  }) async {
    final prefs = _prefs;
    final preferences = <String, Object>{
      for (final key in prefs.getKeys().toList()..sort())
        if (!_notExported.contains(key))
          if (prefs.get(key) case final Object value)
            key: SettingsFile._encodePreference(value),
    };
    final servers = await _ref.read(serverListProvider.future);
    Map<String, Object>? passwords;
    if (passphrase != null) {
      final token = _ref.read(bearwareAccountProvider).token;
      passwords = await PassphraseBox.seal(
        jsonEncode({
          'servers': [
            for (final s in servers)
              if (s.password.isNotEmpty || s.channelPassword.isNotEmpty)
                {
                  'key': _key(s),
                  'password': s.password,
                  'channelPassword': s.channelPassword,
                },
          ],
          if (token.isNotEmpty) 'bearwareToken': token,
        }),
        passphrase,
      );
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': SettingsFile.format,
      'version': 1,
      'app': appVersion,
      'exported': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'preferences': preferences,
      'servers': [
        for (final s in servers)
          s.copyWith(password: '', channelPassword: '').toJson(),
      ],
      'passwords': passwords,
    });
  }

  static String _key(ServerEntry s) => '${s.host}:${s.tcpPort}:${s.username}';

  Future<ImportPreview> preview(SettingsFile file) async {
    final mine = await _ref.read(serverListProvider.future);
    bool known(ServerEntry s) =>
        mine.any((m) => m.host == s.host && m.tcpPort == s.tcpPort);
    final knownCount = file.servers.where(known).length;
    return ImportPreview(
      settings: file.preferences.length,
      newServers: file.servers.length - knownCount,
      knownServers: knownCount,
    );
  }

  Future<Map<String, Object?>> openPasswords(
    SettingsFile file,
    String passphrase,
  ) async {
    final box = file.passwords;
    if (box == null) return const {};
    final String text;
    try {
      text = await PassphraseBox.open(box, passphrase);
    } on WrongPassphrase {
      throw const SettingsPassphraseWrong();
    }
    final opened = jsonDecode(text);
    return opened is Map ? opened.cast<String, Object?>() : const {};
  }

  Future<void> apply(
    SettingsFile file, {
    Map<String, Object?> passwords = const {},
  }) async {
    final prefs = _prefs;
    for (final MapEntry(:key, :value) in file.preferences.entries) {
      if (_notExported.contains(key)) continue;
      await switch (value) {
        bool() => prefs.setBool(key, value),
        int() => prefs.setInt(key, value),
        double() => prefs.setDouble(key, value),
        List<String>() => prefs.setStringList(key, value),
        _ => prefs.setString(key, '$value'),
      };
    }

    final secretServers = <String, Map<Object?, Object?>>{
      for (final item in (passwords['servers'] as List? ?? const []))
        if (item is Map && item['key'] is String) item['key'] as String: item,
    };
    final servers = [
      for (final s in file.servers)
        if (secretServers[_key(s)] case final secret?)
          s.copyWith(
            password: secret['password'] as String? ?? '',
            channelPassword: secret['channelPassword'] as String? ?? '',
          )
        else
          s,
    ];
    if (servers.isNotEmpty) {
      await _ref.read(serverListProvider.notifier).importEntries(servers);
    }
    final token = passwords['bearwareToken'];
    if (token is String && token.isNotEmpty) {
      final username = prefs.getString('bearware_username') ?? '';
      _ref.invalidate(bearwareAccountProvider);
      _ref
          .read(bearwareAccountProvider.notifier)
          .save(BearwareAccount(username: username, token: token));
    }

    _ref
      ..invalidate(settingsProvider)
      ..invalidate(eventConfigProvider)
      ..invalidate(chatTemplatesProvider)
      ..invalidate(timestampFormatProvider)
      ..invalidate(channelSortProvider)
      ..invalidate(fileSortProvider)
      ..invalidate(selectedSoundPackProvider)
      ..invalidate(userConfigsProvider)
      ..invalidate(bearwareAccountProvider);
    await _ref.read(secretStoreProvider).flush();
  }
}
