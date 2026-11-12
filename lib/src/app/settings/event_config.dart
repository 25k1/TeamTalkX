import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/l10n.dart';
import 'locale_providers.dart';
import 'settings_providers.dart';

enum HapticStrength { light, medium, heavy }

class HapticStep {
  const HapticStep(this.strength, this.gapMs);

  final HapticStrength strength;

  final int gapMs;
}

String encodeHaptic(List<HapticStep> pattern) =>
    pattern.map((s) => '${s.strength.name[0]}:${s.gapMs}').join(',');

List<HapticStep> decodeHaptic(String encoded) {
  if (encoded.isEmpty) return const [];
  final steps = <HapticStep>[];
  for (final part in encoded.split(',')) {
    final bits = part.split(':');
    if (bits.length != 2) continue;
    final strength = HapticStrength.values.firstWhere(
      (s) => s.name[0] == bits[0],
      orElse: () => HapticStrength.medium,
    );
    steps.add(HapticStep(strength, int.tryParse(bits[1]) ?? 0));
  }
  return steps;
}

const _joinPulse = [
  HapticStep(HapticStrength.light, 100),
  HapticStep(HapticStrength.medium, 100),
  HapticStep(HapticStrength.heavy, 0),
];
const _leavePulse = [
  HapticStep(HapticStrength.heavy, 100),
  HapticStep(HapticStrength.medium, 100),
  HapticStep(HapticStrength.light, 0),
];
const _txOnPulse = [HapticStep(HapticStrength.medium, 0)];
const _txOffPulse = [HapticStep(HapticStrength.light, 0)];
const _voxOnPulse = [HapticStep(HapticStrength.medium, 0)];
const _voxOffPulse = [HapticStep(HapticStrength.light, 0)];
const _voxModePulse = [HapticStep(HapticStrength.light, 0)];

enum AppEvent {
  userLoggedIn(
    ['nickname', 'username', 'servername'],
    SoundEvent.loggedOn,
    null,
  ),
  userLoggedOut(
    ['nickname', 'username', 'servername'],
    SoundEvent.loggedOff,
    null,
  ),
  userJoined(['nickname', 'username'], SoundEvent.userJoin, _joinPulse),
  userLeft(['nickname', 'username'], SoundEvent.userLeft, _leavePulse),
  userJoinedOther(
    ['nickname', 'username', 'channel'],
    SoundEvent.userJoin,
    null,
    defaultEnabled: false,
  ),
  userLeftOther(
    ['nickname', 'username', 'channel'],
    SoundEvent.userLeft,
    null,
    defaultEnabled: false,
  ),
  channelMessage(['nickname', 'message'], SoundEvent.channelMessage, null),
  channelMessageSent([], SoundEvent.channelMessageSent, null),
  privateMessage(
    ['nickname', 'message'],
    SoundEvent.userMessage,
    null,
    interruptsByDefault: true,
  ),
  broadcastMessage(['nickname', 'message'], SoundEvent.broadcastMessage, null),
  filesUpdated([], SoundEvent.fileUpdate, null, supportsHaptic: false),
  voiceTransmitOn([], SoundEvent.txOn, _txOnPulse, supportsSpeech: false),
  voiceTransmitOff([], SoundEvent.txOff, _txOffPulse, supportsSpeech: false),
  voiceActivationEnabled(
    [],
    SoundEvent.voiceActEnable,
    _voxModePulse,
    supportsSpeech: false,
  ),
  voiceActivationDisabled(
    [],
    SoundEvent.voiceActDisable,
    _voxModePulse,
    supportsSpeech: false,
  ),
  voiceActivationTriggered(
    [],
    SoundEvent.voiceActOn,
    _voxOnPulse,
    supportsSpeech: false,
  ),
  voiceActivationReleased(
    [],
    SoundEvent.voiceActOff,
    _voxOffPulse,
    supportsSpeech: false,
  ),
  connectionLost(
    ['servername'],
    SoundEvent.serverLost,
    null,
    interruptsByDefault: true,
  ),
  kickedFromServer(
    ['kicker', 'servername'],
    SoundEvent.serverLost,
    null,
    interruptsByDefault: true,
  ),
  kickedFromChannel(
    ['kicker', 'channel'],
    null,
    null,
    interruptsByDefault: true,
  );

  const AppEvent(
    this.variables,
    this.defaultSound,
    this.defaultHaptic, {
    this.supportsSpeech = true,
    this.supportsHaptic = true,
    this.defaultEnabled = true,
    this.interruptsByDefault = false,
  });

  final List<String> variables;

  final SoundEvent? defaultSound;

  final List<HapticStep>? defaultHaptic;

  final bool supportsSpeech;
  final bool supportsHaptic;
  final bool defaultEnabled;

  final bool interruptsByDefault;

  static const _messageEvents = {
    AppEvent.channelMessage,
    AppEvent.channelMessageSent,
    AppEvent.privateMessage,
    AppEvent.broadcastMessage,
  };

  bool get supportsChat => supportsSpeech && !_messageEvents.contains(this);
}

String defaultEventTemplate(AppEvent event, AppLocalizations l10n) =>
    switch (event) {
      AppEvent.userLoggedIn => l10n.eventTplUserLoggedIn('{nickname}'),
      AppEvent.userLoggedOut => l10n.eventTplUserLoggedOut('{nickname}'),
      AppEvent.userJoined => l10n.eventTplUserJoined('{nickname}'),
      AppEvent.userLeft => l10n.eventTplUserLeft('{nickname}'),
      AppEvent.userJoinedOther => l10n.eventTplUserJoinedOther(
        '{nickname}',
        '{channel}',
      ),
      AppEvent.userLeftOther => l10n.eventTplUserLeftOther(
        '{nickname}',
        '{channel}',
      ),
      AppEvent.channelMessage => l10n.eventTplChannelMessage(
        '{nickname}',
        '{message}',
      ),
      AppEvent.privateMessage => l10n.eventTplPrivateMessage(
        '{nickname}',
        '{message}',
      ),
      AppEvent.broadcastMessage => l10n.eventTplBroadcastMessage(
        '{nickname}',
        '{message}',
      ),
      AppEvent.filesUpdated => l10n.eventTplFilesUpdated,
      AppEvent.connectionLost => l10n.eventTplConnectionLost,
      AppEvent.kickedFromServer => l10n.eventTplKickedFromServer('{kicker}'),
      AppEvent.kickedFromChannel => l10n.eventTplKickedFromChannel(
        '{channel}',
        '{kicker}',
      ),
      AppEvent.channelMessageSent ||
      AppEvent.voiceTransmitOn ||
      AppEvent.voiceTransmitOff ||
      AppEvent.voiceActivationEnabled ||
      AppEvent.voiceActivationDisabled ||
      AppEvent.voiceActivationTriggered ||
      AppEvent.voiceActivationReleased => '',
    };

class EventConfig {
  const EventConfig({
    required this.enabled,
    required this.speechEnabled,
    this.template,
    required this.soundEnabled,
    required this.soundPath,
    this.soundVolumePercent = 100,
    required this.hapticEnabled,
    required this.haptic,
    required this.chatEnabled,
    this.chatTemplate,
    this.interrupts = false,
  });

  final bool enabled;
  final bool speechEnabled;

  final String? template;

  final bool soundEnabled;

  final String soundPath;

  final int soundVolumePercent;

  final bool hapticEnabled;
  final List<HapticStep> haptic;

  final bool chatEnabled;

  final String? chatTemplate;

  final bool interrupts;

  bool get hasCustomSound => soundPath.isNotEmpty;

  EventConfig copyWith({
    bool? enabled,
    bool? speechEnabled,
    String? template,
    bool? soundEnabled,
    String? soundPath,
    int? soundVolumePercent,
    bool? hapticEnabled,
    List<HapticStep>? haptic,
    bool? chatEnabled,
    String? chatTemplate,
    bool? interrupts,
  }) => EventConfig(
    enabled: enabled ?? this.enabled,
    speechEnabled: speechEnabled ?? this.speechEnabled,
    template: template ?? this.template,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    soundPath: soundPath ?? this.soundPath,
    soundVolumePercent: soundVolumePercent ?? this.soundVolumePercent,
    hapticEnabled: hapticEnabled ?? this.hapticEnabled,
    haptic: haptic ?? this.haptic,
    chatEnabled: chatEnabled ?? this.chatEnabled,
    chatTemplate: chatTemplate ?? this.chatTemplate,
    interrupts: interrupts ?? this.interrupts,
  );
}

final eventConfigProvider =
    NotifierProvider<EventConfigNotifier, Map<AppEvent, EventConfig>>(
      EventConfigNotifier.new,
    );

class EventConfigNotifier extends Notifier<Map<AppEvent, EventConfig>> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Map<AppEvent, EventConfig> build() {
    final prefs = _prefs;
    return {for (final event in AppEvent.values) event: _load(prefs, event)};
  }

  EventConfig _load(SharedPreferences prefs, AppEvent event) {
    final key = 'event.${event.name}';
    final encodedHaptic = prefs.getString('$key.haptic_pattern');
    return EventConfig(
      enabled: prefs.getBool('$key.enabled') ?? event.defaultEnabled,
      speechEnabled:
          event.supportsSpeech && (prefs.getBool('$key.speech') ?? true),
      template: prefs.getString('$key.template'),
      soundEnabled: prefs.getBool('$key.sound') ?? (event.defaultSound != null),
      soundPath: prefs.getString('$key.sound_path') ?? '',
      soundVolumePercent: prefs.getInt('$key.sound_volume') ?? 100,
      hapticEnabled:
          event.supportsHaptic &&
          (prefs.getBool('$key.haptic') ?? (event.defaultHaptic != null)),
      haptic: encodedHaptic != null
          ? decodeHaptic(encodedHaptic)
          : (event.defaultHaptic ?? const []),
      chatEnabled: prefs.getBool('$key.chat') ?? false,
      chatTemplate: prefs.getString('$key.chat_template'),
      interrupts: prefs.getBool('$key.interrupt') ?? event.interruptsByDefault,
    );
  }

  EventConfig of(AppEvent event) => state[event]!;

  String speechTemplate(AppEvent event) =>
      of(event).template ??
      defaultEventTemplate(event, ref.read(appLocalizationsProvider));

  String chatTemplateOf(AppEvent event) =>
      of(event).chatTemplate ??
      defaultEventTemplate(event, ref.read(appLocalizationsProvider));

  void resetTemplate(AppEvent event) {
    unawaited(_prefs.remove('event.${event.name}.template'));
    _update(event, _load(_prefs, event));
  }

  void resetChatTemplate(AppEvent event) {
    unawaited(_prefs.remove('event.${event.name}.chat_template'));
    _update(event, _load(_prefs, event));
  }

  void _update(AppEvent event, EventConfig config) {
    state = {...state, event: config};
  }

  void setEnabled(AppEvent event, bool value) {
    unawaited(_prefs.setBool('event.${event.name}.enabled', value));
    _update(event, of(event).copyWith(enabled: value));
  }

  void setSpeechEnabled(AppEvent event, bool value) {
    unawaited(_prefs.setBool('event.${event.name}.speech', value));
    _update(event, of(event).copyWith(speechEnabled: value));
  }

  void setTemplate(AppEvent event, String template) {
    unawaited(_prefs.setString('event.${event.name}.template', template));
    _update(event, of(event).copyWith(template: template));
  }

  void setSoundEnabled(AppEvent event, bool value) {
    unawaited(_prefs.setBool('event.${event.name}.sound', value));
    _update(event, of(event).copyWith(soundEnabled: value));
  }

  void setSoundPath(AppEvent event, String path) {
    unawaited(_prefs.setString('event.${event.name}.sound_path', path));
    _update(event, of(event).copyWith(soundPath: path));
  }

  void setSoundVolume(AppEvent event, int percent) {
    unawaited(_prefs.setInt('event.${event.name}.sound_volume', percent));
    _update(event, of(event).copyWith(soundVolumePercent: percent));
  }

  void setHapticEnabled(AppEvent event, bool value) {
    unawaited(_prefs.setBool('event.${event.name}.haptic', value));
    _update(event, of(event).copyWith(hapticEnabled: value));
  }

  void setHaptic(AppEvent event, List<HapticStep> pattern) {
    unawaited(
      _prefs.setString(
        'event.${event.name}.haptic_pattern',
        encodeHaptic(pattern),
      ),
    );
    _update(event, of(event).copyWith(haptic: pattern));
  }

  void setChatEnabled(AppEvent event, bool value) {
    unawaited(_prefs.setBool('event.${event.name}.chat', value));
    _update(event, of(event).copyWith(chatEnabled: value));
  }

  void setInterrupts(AppEvent event, bool value) {
    unawaited(_prefs.setBool('event.${event.name}.interrupt', value));
    _update(event, of(event).copyWith(interrupts: value));
  }

  void setChatTemplate(AppEvent event, String template) {
    unawaited(_prefs.setString('event.${event.name}.chat_template', template));
    _update(event, of(event).copyWith(chatTemplate: template));
  }
}
