import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/secret_store.dart';
import '../../data/tt_format.dart';
import '../../diagnostics/log.dart';
import '../../domain/server_entry.dart';
import '../security/secrets.dart';

final serverListProvider =
    AsyncNotifierProvider<ServerListNotifier, List<ServerEntry>>(
      ServerListNotifier.new,
    );

class ServerListNotifier extends AsyncNotifier<List<ServerEntry>> {
  static const _prefsKey = 'server_list';

  static const _secretsKey = 'servers';

  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  Future<List<ServerEntry>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json == null) return const [];
    final entries = ServerEntry.decodeList(json);
    if (entries.any(_hasSecrets)) {
      appLog.i('secrets', 'Moving server passwords to the secret store');
      await _persist(prefs, entries);
      return entries;
    }
    return _withSecrets(entries);
  }

  static bool _hasSecrets(ServerEntry e) =>
      e.password.isNotEmpty || e.channelPassword.isNotEmpty;

  static String _key(ServerEntry e) => '${e.host}:${e.tcpPort}:${e.username}';

  List<ServerEntry> _withSecrets(List<ServerEntry> entries) {
    final saved = _secrets.read(_secretsKey);
    if (saved == null) return entries;
    final byKey = <String, List<Map<String, Object?>>>{};
    try {
      for (final item
          in (jsonDecode(saved) as List).cast<Map<String, Object?>>()) {
        byKey.putIfAbsent(item['key'] as String? ?? '', () => []).add(item);
      }
    } on FormatException {
      return entries;
    } on TypeError {
      return entries;
    }
    final merged = <ServerEntry>[];
    for (final entry in entries) {
      final items = byKey[_key(entry)];
      if (items == null || items.isEmpty) {
        merged.add(entry);
        continue;
      }
      final item = items.removeAt(0);
      merged.add(
        entry.copyWith(
          password: item['password'] as String? ?? '',
          channelPassword: item['channelPassword'] as String? ?? '',
        ),
      );
    }
    return merged;
  }

  Future<void> _persist(
    SharedPreferences prefs,
    List<ServerEntry> entries,
  ) async {
    await _secrets.write(
      _secretsKey,
      entries.any(_hasSecrets)
          ? jsonEncode([
              for (final e in entries)
                {
                  'key': _key(e),
                  'password': e.password,
                  'channelPassword': e.channelPassword,
                },
            ])
          : null,
    );
    await prefs.setString(
      _prefsKey,
      ServerEntry.encodeList([
        for (final e in entries) e.copyWith(password: '', channelPassword: ''),
      ]),
    );
  }

  Future<void> _save(List<ServerEntry> entries) async {
    state = AsyncData(entries);
    await _persist(await SharedPreferences.getInstance(), entries);
  }

  List<ServerEntry> get _current => state.value ?? const [];

  Future<void> add(ServerEntry entry) => _save([..._current, entry]);

  Future<void> updateAt(int index, ServerEntry entry) async {
    final entries = [..._current];
    if (index < 0 || index >= entries.length) return;
    entries[index] = entry;
    await _save(entries);
  }

  Future<void> insertAt(int index, ServerEntry entry) async {
    final entries = [..._current];
    entries.insert(index.clamp(0, entries.length), entry);
    await _save(entries);
  }

  Future<void> removeAt(int index) async {
    final entries = [..._current];
    if (index < 0 || index >= entries.length) return;
    entries.removeAt(index);
    await _save(entries);
  }

  Future<void> updateChannel(
    int index,
    ServerEntry entry, {
    required String path,
    required String password,
  }) async {
    final entries = [..._current];
    if (index < 0 || index >= entries.length) return;
    final saved = entries[index];
    if (saved.host != entry.host || saved.tcpPort != entry.tcpPort) return;
    entries[index] = saved.copyWith(channel: path, channelPassword: password);
    await _save(entries);
  }

  Future<void> moveWithin(List<int> slots, int from, int to) async {
    final entries = [..._current];
    if (from == to ||
        slots.any((i) => i < 0 || i >= entries.length) ||
        from < 0 ||
        to < 0 ||
        from >= slots.length ||
        to >= slots.length) {
      return;
    }
    final group = [for (final i in slots) entries[i]];
    final moved = group.removeAt(from);
    group.insert(to, moved);
    for (final (n, i) in slots.indexed) {
      entries[i] = group[n];
    }
    await _save(entries);
  }

  Future<int> duplicate(int index, {required String name}) async {
    final entries = [..._current];
    if (index < 0 || index >= entries.length) return -1;
    final copy = entries[index].copyWith(name: name, connectOnStartup: false);
    entries.insert(
      index + 1,
      ServerEntry.fromJson(copy.toJson()..remove('lastConnected')),
    );
    await _save(entries);
    return index + 1;
  }

  Future<void> setFavorite(int index, {required bool favorite}) async {
    final entries = [..._current];
    if (index < 0 || index >= entries.length) return;
    entries[index] = entries[index].copyWith(favorite: favorite);
    await _save(entries);
  }

  Future<void> setConnectOnStartup(int index, {required bool connect}) async {
    final entries = [
      for (final (i, e) in _current.indexed)
        e.copyWith(connectOnStartup: connect && i == index),
    ];
    await _save(entries);
  }

  Future<void> markConnected(ServerEntry entry, {DateTime? now}) async {
    final entries = [..._current];
    final index = entries.indexWhere(
      (e) =>
          e.host == entry.host &&
          e.tcpPort == entry.tcpPort &&
          e.username == entry.username,
    );
    if (index < 0) return;
    entries[index] = entries[index].copyWith(
      lastConnected: now ?? DateTime.now(),
    );
    await _save(entries);
  }

  (ServerEntry, int)? get startupServer {
    for (final (i, e) in _current.indexed) {
      if (e.connectOnStartup) return (e, i);
    }
    return null;
  }

  Future<int> importEntries(List<ServerEntry> imported) async {
    final entries = [..._current];
    var added = 0;
    for (final entry in imported) {
      final duplicate = entries.any(
        (e) => e.host == entry.host && e.tcpPort == entry.tcpPort,
      );
      if (!duplicate) {
        entries.add(entry);
        added++;
      }
    }
    if (added > 0) await _save(entries);
    return added;
  }

  Future<(int, int)> importTtFile(String xml) async {
    final imported = decodeTtFile(xml);
    if (imported.isEmpty) return (0, 0);
    return (imported.length, await importEntries(imported));
  }
}

List<ServerEntry> serversInTtFile(String xml) => decodeTtFile(xml);

String exportTtFile(List<ServerEntry> entries) => encodeTtFile(entries);

ServerEntry? serverFromTtLink(String url) => parseTtLink(url);
