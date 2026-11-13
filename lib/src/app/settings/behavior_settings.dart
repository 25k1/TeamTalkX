import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/media_keys.dart';
import 'prefs_notifier.dart';
import 'settings_types.dart';

class KeySettings {
  const KeySettings({
    this.pttKeyCode = 0,
    this.pttKeyLabel = '',
    this.keyBindings = const KeyBindings(),
  });

  final int pttKeyCode;
  final String pttKeyLabel;
  final KeyBindings keyBindings;

  KeySettings copyWith({
    int? pttKeyCode,
    String? pttKeyLabel,
    KeyBindings? keyBindings,
  }) => KeySettings(
    pttKeyCode: pttKeyCode ?? this.pttKeyCode,
    pttKeyLabel: pttKeyLabel ?? this.pttKeyLabel,
    keyBindings: keyBindings ?? this.keyBindings,
  );
}

final keySettingsProvider = NotifierProvider<KeySettingsNotifier, KeySettings>(
  KeySettingsNotifier.new,
);

class KeySettingsNotifier extends PrefsNotifier<KeySettings> {
  @override
  KeySettings build() => KeySettings(
    pttKeyCode: prefs.getInt('ptt_key_code') ?? 0,
    pttKeyLabel: prefs.getString('ptt_key_label') ?? '',
    keyBindings: KeyBindings.decode(prefs.getString('media_key_bindings')),
  );

  void setPttKey(int keyCode, String label) {
    unawaited(prefs.setInt('ptt_key_code', keyCode));
    unawaited(prefs.setString('ptt_key_label', label));
    state = state.copyWith(pttKeyCode: keyCode, pttKeyLabel: label);
  }

  void setKeyAction(MediaKey key, KeyPress press, KeyAction? action) {
    final bindings = state.keyBindings.withAction(key, press, action);
    saveString(
      'media_key_bindings',
      bindings.encode(),
      (s) => s.copyWith(keyBindings: bindings),
    );
  }
}

class InterruptionSettings {
  const InterruptionSettings({
    this.focusLossPolicy = FocusLossPolicy.ignore,
    this.duckOthersForVoice = false,
    this.duckOthersForEvents = false,
    this.keepVolumeUnderTalkBack = false,
    this.awayDuringCalls = true,
    this.callStatusMessage = '',
  });

  final FocusLossPolicy focusLossPolicy;
  final bool duckOthersForVoice;
  final bool duckOthersForEvents;
  final bool keepVolumeUnderTalkBack;
  final bool awayDuringCalls;
  final String callStatusMessage;

  InterruptionSettings copyWith({
    FocusLossPolicy? focusLossPolicy,
    bool? duckOthersForVoice,
    bool? duckOthersForEvents,
    bool? keepVolumeUnderTalkBack,
    bool? awayDuringCalls,
    String? callStatusMessage,
  }) => InterruptionSettings(
    focusLossPolicy: focusLossPolicy ?? this.focusLossPolicy,
    duckOthersForVoice: duckOthersForVoice ?? this.duckOthersForVoice,
    duckOthersForEvents: duckOthersForEvents ?? this.duckOthersForEvents,
    keepVolumeUnderTalkBack:
        keepVolumeUnderTalkBack ?? this.keepVolumeUnderTalkBack,
    awayDuringCalls: awayDuringCalls ?? this.awayDuringCalls,
    callStatusMessage: callStatusMessage ?? this.callStatusMessage,
  );
}

final interruptionSettingsProvider =
    NotifierProvider<InterruptionSettingsNotifier, InterruptionSettings>(
      InterruptionSettingsNotifier.new,
    );

class InterruptionSettingsNotifier extends PrefsNotifier<InterruptionSettings> {
  @override
  InterruptionSettings build() => InterruptionSettings(
    focusLossPolicy: FocusLossPolicy.fromName(
      prefs.getString('focus_loss_policy'),
    ),
    duckOthersForVoice: prefs.getBool('duck_others_voice') ?? false,
    duckOthersForEvents: prefs.getBool('duck_others_events') ?? false,
    keepVolumeUnderTalkBack:
        prefs.getBool('keep_volume_under_talkback') ?? false,
    awayDuringCalls: prefs.getBool('pause_during_calls') ?? true,
    callStatusMessage: prefs.getString('call_status_message') ?? '',
  );

  void setFocusLossPolicy(FocusLossPolicy v) => saveString(
    'focus_loss_policy',
    v.name,
    (s) => s.copyWith(focusLossPolicy: v),
  );

  void setDuckOthersForVoice(bool v) => saveBool(
    'duck_others_voice',
    v,
    (s) => s.copyWith(duckOthersForVoice: v),
  );

  void setDuckOthersForEvents(bool v) => saveBool(
    'duck_others_events',
    v,
    (s) => s.copyWith(duckOthersForEvents: v),
  );

  void setKeepVolumeUnderTalkBack(bool v) => saveBool(
    'keep_volume_under_talkback',
    v,
    (s) => s.copyWith(keepVolumeUnderTalkBack: v),
  );

  void setAwayDuringCalls(bool v) =>
      saveBool('pause_during_calls', v, (s) => s.copyWith(awayDuringCalls: v));

  void setCallStatusMessage(String v) => saveString(
    'call_status_message',
    v.trim(),
    (s) => s.copyWith(callStatusMessage: v.trim()),
  );
}

class ConnectionSettings {
  const ConnectionSettings({
    this.autoJoinRootChannel = true,
    this.keepAwakeWhileConnected = false,
  });

  final bool autoJoinRootChannel;
  final bool keepAwakeWhileConnected;

  ConnectionSettings copyWith({
    bool? autoJoinRootChannel,
    bool? keepAwakeWhileConnected,
  }) => ConnectionSettings(
    autoJoinRootChannel: autoJoinRootChannel ?? this.autoJoinRootChannel,
    keepAwakeWhileConnected:
        keepAwakeWhileConnected ?? this.keepAwakeWhileConnected,
  );
}

final connectionSettingsProvider =
    NotifierProvider<ConnectionSettingsNotifier, ConnectionSettings>(
      ConnectionSettingsNotifier.new,
    );

class ConnectionSettingsNotifier extends PrefsNotifier<ConnectionSettings> {
  @override
  ConnectionSettings build() => ConnectionSettings(
    autoJoinRootChannel: prefs.getBool('auto_join_root_channel') ?? true,
    keepAwakeWhileConnected:
        prefs.getBool('keep_awake_while_connected') ?? false,
  );

  void setAutoJoinRootChannel(bool v) => saveBool(
    'auto_join_root_channel',
    v,
    (s) => s.copyWith(autoJoinRootChannel: v),
  );

  void setKeepAwakeWhileConnected(bool v) => saveBool(
    'keep_awake_while_connected',
    v,
    (s) => s.copyWith(keepAwakeWhileConnected: v),
  );
}

class ServerListSettings {
  const ServerListSettings({
    this.showOfficialServers = true,
    this.showUnofficialServers = false,
  });

  final bool showOfficialServers;
  final bool showUnofficialServers;

  ServerListSettings copyWith({
    bool? showOfficialServers,
    bool? showUnofficialServers,
  }) => ServerListSettings(
    showOfficialServers: showOfficialServers ?? this.showOfficialServers,
    showUnofficialServers: showUnofficialServers ?? this.showUnofficialServers,
  );
}

final serverListSettingsProvider =
    NotifierProvider<ServerListSettingsNotifier, ServerListSettings>(
      ServerListSettingsNotifier.new,
    );

class ServerListSettingsNotifier extends PrefsNotifier<ServerListSettings> {
  @override
  ServerListSettings build() => ServerListSettings(
    showOfficialServers: prefs.getBool('show_official_servers') ?? true,
    showUnofficialServers: prefs.getBool('show_unofficial_servers') ?? false,
  );

  void setShowOfficialServers(bool v) => saveBool(
    'show_official_servers',
    v,
    (s) => s.copyWith(showOfficialServers: v),
  );

  void setShowUnofficialServers(bool v) => saveBool(
    'show_unofficial_servers',
    v,
    (s) => s.copyWith(showUnofficialServers: v),
  );
}

class ChatSettings {
  const ChatSettings({this.chatRetentionDays = 90});

  final int chatRetentionDays;
}

final chatSettingsProvider =
    NotifierProvider<ChatSettingsNotifier, ChatSettings>(
      ChatSettingsNotifier.new,
    );

class ChatSettingsNotifier extends PrefsNotifier<ChatSettings> {
  @override
  ChatSettings build() => ChatSettings(
    chatRetentionDays: prefs.getInt('chat_retention_days') ?? 90,
  );

  void setChatRetentionDays(int v) => saveInt(
    'chat_retention_days',
    v,
    (_) => ChatSettings(chatRetentionDays: v),
  );
}
