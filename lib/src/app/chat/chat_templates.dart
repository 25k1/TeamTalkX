import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../settings/locale_providers.dart';
import '../settings/persisted_notifier.dart';
import '../settings/settings_providers.dart';

const _channelVars = [
  '{date}',
  '{channelpath}',
  '{channelname}',
  '{channeltopic}',
  '{quota}',
];

const _messageVars = ['{date}', '{user}', '{content}'];

enum ChatTemplate {
  channelMessage('chat_tpl_channel', _messageVars),
  broadcastMessage('chat_tpl_broadcast', _messageVars),
  privateMessage('chat_tpl_private', _messageVars),
  logMessage('chat_tpl_log', ['{date}', '{content}']),
  serverName('chat_tpl_servername', ['{date}', '{server}']),
  serverMotd('chat_tpl_motd', ['{date}', '{MOTD}']),
  joinedChannel('chat_tpl_joinchan', _channelVars),
  channelTopic('chat_tpl_chantopic', _channelVars),
  channelQuota('chat_tpl_diskquota', _channelVars);

  const ChatTemplate(this.prefsKey, this.variables);

  final String prefsKey;

  final List<String> variables;

  bool get isMessage => switch (this) {
    channelMessage || broadcastMessage || privateMessage || logMessage => true,
    _ => false,
  };
}

String defaultChatTemplate(ChatTemplate t, AppLocalizations l10n) =>
    switch (t) {
      ChatTemplate.channelMessage => l10n.chatTplChannel(
        '{date}',
        '{user}',
        '{content}',
      ),
      ChatTemplate.broadcastMessage => l10n.chatTplBroadcast(
        '{date}',
        '{user}',
        '{content}',
      ),
      ChatTemplate.privateMessage => l10n.chatTplPrivate(
        '{date}',
        '{user}',
        '{content}',
      ),
      ChatTemplate.logMessage => l10n.chatTplLog('{date}', '{content}'),
      ChatTemplate.serverName => l10n.chatTplServerName('{date}', '{server}'),
      ChatTemplate.serverMotd => l10n.chatTplMotd('{date}', '{MOTD}'),
      ChatTemplate.joinedChannel => l10n.chatTplJoined(
        '{date}',
        '{channelpath}',
      ),
      ChatTemplate.channelTopic => l10n.chatTplTopic('{channeltopic}'),
      ChatTemplate.channelQuota => l10n.chatTplQuota('{quota}'),
    };

final chatTemplatesProvider =
    NotifierProvider<ChatTemplatesNotifier, Map<ChatTemplate, String>>(
      ChatTemplatesNotifier.new,
    );

class ChatTemplatesNotifier extends Notifier<Map<ChatTemplate, String>> {
  @override
  Map<ChatTemplate, String> build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return {
      for (final t in ChatTemplate.values) t: ?prefs.getString(t.prefsKey),
    };
  }

  String of(ChatTemplate t) =>
      state[t] ?? defaultChatTemplate(t, ref.read(appLocalizationsProvider));

  void setTemplate(ChatTemplate t, String value) {
    unawaited(ref.read(sharedPreferencesProvider).setString(t.prefsKey, value));
    state = {...state, t: value};
  }

  void reset(ChatTemplate t) {
    unawaited(ref.read(sharedPreferencesProvider).remove(t.prefsKey));
    state = {...state}..remove(t);
  }

  void resetAll() {
    final prefs = ref.read(sharedPreferencesProvider);
    for (final t in ChatTemplate.values) {
      unawaited(prefs.remove(t.prefsKey));
    }
    state = const {};
  }

  String format(ChatTemplate t, Map<String, String> vars) {
    var out = of(t);
    vars.forEach((token, value) => out = out.replaceAll(token, value));
    return out;
  }
}

const timestampVariables = [
  '{year}',
  '{month}',
  '{day}',
  '{hour}',
  '{hour12}',
  '{minute}',
  '{second}',
  '{ampm}',
];

const defaultTimestampFormat = '{year}-{month}-{day} {hour}:{minute}:{second}';

final timestampFormatProvider =
    NotifierProvider<TimestampFormatNotifier, String>(
      TimestampFormatNotifier.new,
    );

class TimestampFormatNotifier extends PersistedStringNotifier {
  @override
  String get prefsKey => 'chat_timestamp_format';
  @override
  String get defaultValue => defaultTimestampFormat;
}

String formatTimestamp(String format, DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final vars = {
    '{year}': time.year.toString().padLeft(4, '0'),
    '{month}': two(time.month),
    '{day}': two(time.day),
    '{hour}': two(time.hour),
    '{hour12}': two(hour12),
    '{minute}': two(time.minute),
    '{second}': two(time.second),
    '{ampm}': time.hour < 12 ? 'AM' : 'PM',
  };
  var out = format;
  vars.forEach((token, value) => out = out.replaceAll(token, value));
  return out;
}
