import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../../domain/models.dart';
import '../../domain/sound_level.dart';
import '../../domain/tt_types.dart';
import '../connection/connection_providers.dart';
import '../settings/settings_providers.dart';

final kManagedSubscriptions =
    Subscriptions.voice |
    Subscriptions.channelMsg |
    Subscriptions.userMsg |
    Subscriptions.broadcastMsg |
    Subscriptions.customMsg |
    Subscriptions.mediaFile;

final kInterceptSubscriptions =
    Subscriptions.interceptUserMsg |
    Subscriptions.interceptChannelMsg |
    Subscriptions.interceptCustomMsg |
    Subscriptions.interceptVoice |
    Subscriptions.interceptMediaFile;

class StoredUserConfig {
  const StoredUserConfig({
    required this.username,
    this.clientName = '',
    this.muted = false,
    this.volumePercent,
    this.mediaMuted = false,
    this.mediaVolumePercent,
    this.subscriptions,
  });

  final String username;

  final String clientName;
  final bool muted;
  final int? volumePercent;
  final bool mediaMuted;
  final int? mediaVolumePercent;

  final int? subscriptions;

  String get key => clientName.isEmpty ? username : '$username $clientName';

  Map<String, dynamic> toJson() => {
    'username': username,
    if (clientName.isNotEmpty) 'client': clientName,
    'muted': muted,
    if (volumePercent != null) 'volume': volumePercent,
    'mediaMuted': mediaMuted,
    if (mediaVolumePercent != null) 'mediaVolume': mediaVolumePercent,
    if (subscriptions != null) 'subscriptions': subscriptions,
    if (subscriptions != null) 'subscriptionsVersion': 2,
  };

  static int? _subscriptionsFrom(Map<String, dynamic> json) {
    final stored = (json['subscriptions'] as num?)?.toInt();
    if (stored == null || json['subscriptionsVersion'] != null) return stored;
    return stored | Subscriptions.broadcastMsg | Subscriptions.customMsg;
  }

  factory StoredUserConfig.fromJson(Map<String, dynamic> json) =>
      StoredUserConfig(
        username: json['username'] as String? ?? '',
        clientName: json['client'] as String? ?? '',
        muted: json['muted'] as bool? ?? false,
        volumePercent: (json['volume'] as num?)?.toInt(),
        mediaMuted: json['mediaMuted'] as bool? ?? false,
        mediaVolumePercent: (json['mediaVolume'] as num?)?.toInt(),
        subscriptions: _subscriptionsFrom(json),
      );
}

final userConfigsProvider =
    NotifierProvider<
      UserConfigsNotifier,
      Map<String, Map<String, StoredUserConfig>>
    >(UserConfigsNotifier.new);

class UserConfigsNotifier
    extends Notifier<Map<String, Map<String, StoredUserConfig>>> {
  static const _prefsKey = 'user_configs';

  @override
  Map<String, Map<String, StoredUserConfig>> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (raw == null) return {};
    return _decode(raw);
  }

  Map<String, Map<String, StoredUserConfig>> _decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final server in map.entries)
          server.key: {
            for (final cfg in (server.value as List))
              StoredUserConfig.fromJson(cfg as Map<String, dynamic>).key:
                  StoredUserConfig.fromJson(cfg),
          },
      };
    } on FormatException catch (e) {
      appLog.w('users', 'Stored user settings are not valid JSON', e);
      return {};
    } on TypeError catch (e) {
      appLog.w('users', 'Stored user settings have an unexpected shape', e);
      return {};
    }
  }

  void _persist() {
    final json = {
      for (final server in state.entries)
        server.key: [for (final cfg in server.value.values) cfg.toJson()],
    };
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(_prefsKey, jsonEncode(json)),
    );
  }

  StoredUserConfig? lookup(
    String serverKey,
    String username,
    String clientName,
  ) {
    final byUser = state[serverKey];
    if (byUser == null) return null;
    return byUser['$username $clientName'] ?? byUser[username];
  }

  void upsert(String serverKey, StoredUserConfig config) {
    final byUser = {...?state[serverKey], config.key: config};
    state = {...state, serverKey: byUser};
    _persist();
  }

  void remove(String serverKey, String key) {
    final byUser = {...?state[serverKey]}..remove(key);
    state = {...state, if (byUser.isNotEmpty) serverKey: byUser};
    if (byUser.isEmpty) {
      state = {...state}..remove(serverKey);
    }
    _persist();
  }

  void clearAll() {
    state = {};
    _persist();
  }

  String exportJson() {
    final json = {
      for (final server in state.entries)
        server.key: [for (final cfg in server.value.values) cfg.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  int importJson(String raw) {
    final decoded = _decode(raw);
    if (decoded.isEmpty) {
      try {
        jsonDecode(raw);
      } on FormatException {
        return -1;
      }
    }
    var count = 0;
    final merged = {
      for (final server in state.entries) server.key: {...server.value},
    };
    for (final server in decoded.entries) {
      final byUser = merged.putIfAbsent(server.key, () => {});
      for (final cfg in server.value.values) {
        byUser[cfg.key] = cfg;
        count++;
      }
    }
    state = merged;
    _persist();
    return count;
  }
}

String effectiveUsername(
  TtUser user, {
  required int myUserId,
  String? loginUsername,
}) {
  if (user.username.isNotEmpty) return user.username;
  if (user.id == myUserId) return loginUsername ?? '';
  return user.username;
}

final userConfigApplyProvider = Provider<void>((ref) {
  final client = ref.watch(teamTalkClientProvider);
  final applied = <int>{};

  void apply(TtUser user) {
    if (applied.contains(user.id)) return;
    applied.add(user.id);
    final serverKey = ref.read(connectionProvider.notifier).currentServerKey;
    if (serverKey == null) return;
    final username = effectiveUsername(
      user,
      myUserId: client.state.myUserId,
      loginUsername: ref
          .read(connectionProvider.notifier)
          .currentEntry
          ?.username,
    );
    final cfg = ref
        .read(userConfigsProvider.notifier)
        .lookup(serverKey, username, user.clientName);
    if (cfg == null) return;

    client.setUserMute(user.id, muted: cfg.muted);
    if (cfg.volumePercent != null) {
      client.setUserVolume(user.id, volumeFromPercent(cfg.volumePercent!));
    }
    client.setUserMute(user.id, muted: cfg.mediaMuted, media: true);
    if (cfg.mediaVolumePercent != null) {
      client.setUserVolume(
        user.id,
        volumeFromPercent(cfg.mediaVolumePercent!),
        media: true,
      );
    }
    if (cfg.subscriptions != null) {
      var managed = kManagedSubscriptions;
      var want = cfg.subscriptions!;
      if (client.isAdmin) {
        managed |= kInterceptSubscriptions;
      } else {
        want &= ~kInterceptSubscriptions;
      }
      final wanted = want & managed;
      if (wanted != 0) unawaited(client.subscribe(user.id, wanted));
      final unwanted = managed & ~wanted;
      if (unwanted != 0) unawaited(client.unsubscribe(user.id, unwanted));
    }
  }

  final sub = client.events.listen((event) {
    switch (event) {
      case ConLostEvent() || MyselfLoggedOutEvent():
        applied.clear();
      case UserLoggedOutEvent(:final user):
        applied.remove(user.id);
      case UserLoggedInEvent(:final user) || UserJoinedEvent(:final user):
        apply(user);
      default:
        break;
    }
  });
  ref.onDispose(sub.cancel);
});
