library;

import '../../app/channels/channel_tree_providers.dart';
import '../../app/chat/chat_templates.dart';
import '../../app/files/file_providers.dart';
import '../../app/files/sort.dart';
import '../../app/settings/event_config.dart';
import '../../app/settings/settings_providers.dart';
import '../../domain/app_permission.dart';
import '../../domain/media_keys.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';

extension ChannelSortLabel on ChannelSort {
  String label(AppLocalizations l10n) => switch (this) {
    ChannelSort.name => l10n.channelSortName,
    ChannelSort.popularity => l10n.channelSortPopularity,
  };
}

extension FileSortFieldLabel on FileSortField {
  String label(AppLocalizations l10n) => switch (this) {
    FileSortField.name => l10n.filesSortName,
    FileSortField.size => l10n.filesSortSize,
    FileSortField.owner => l10n.filesSortOwner,
    FileSortField.date => l10n.filesSortDate,
  };
}

extension UserStatusLabel on UserStatus {
  String label(AppLocalizations l10n) => switch (this) {
    UserStatus.available => l10n.statusAvailable,
    UserStatus.away => l10n.statusAway,
    UserStatus.question => l10n.statusQuestion,
  };
}

extension GenderLabel on Gender {
  String label(AppLocalizations l10n) => switch (this) {
    Gender.male => l10n.genderMale,
    Gender.female => l10n.genderFemale,
    Gender.neutral => l10n.genderNeutral,
  };
}

extension StereoChannelLabel on StereoChannel {
  String label(AppLocalizations l10n) => switch (this) {
    StereoChannel.both => l10n.stereoBoth,
    StereoChannel.left => l10n.stereoLeft,
    StereoChannel.right => l10n.stereoRight,
  };
}

extension HapticStrengthLabel on HapticStrength {
  String label(AppLocalizations l10n) => switch (this) {
    HapticStrength.light => l10n.hapticLight,
    HapticStrength.medium => l10n.hapticMedium,
    HapticStrength.heavy => l10n.hapticHeavy,
  };
}

extension SoundEventLabel on SoundEvent {
  String label(AppLocalizations l10n) => switch (this) {
    SoundEvent.userJoin => l10n.soundEventUserJoin,
    SoundEvent.userLeft => l10n.soundEventUserLeft,
    SoundEvent.loggedOn => l10n.soundEventLoggedOn,
    SoundEvent.loggedOff => l10n.soundEventLoggedOff,
    SoundEvent.channelMessage => l10n.soundEventChannelMessage,
    SoundEvent.channelMessageSent => l10n.soundEventChannelMessageSent,
    SoundEvent.userMessage => l10n.soundEventUserMessage,
    SoundEvent.broadcastMessage => l10n.soundEventBroadcastMessage,
    SoundEvent.serverLost => l10n.soundEventServerLost,
    SoundEvent.txOn => l10n.soundEventTxOn,
    SoundEvent.txOff => l10n.soundEventTxOff,
    SoundEvent.voiceActEnable => l10n.soundEventVoxEnable,
    SoundEvent.voiceActDisable => l10n.soundEventVoxDisable,
    SoundEvent.voiceActOn => l10n.soundEventVoxOn,
    SoundEvent.voiceActOff => l10n.soundEventVoxOff,
    SoundEvent.fileUpdate => l10n.soundEventFileUpdate,
    SoundEvent.typing => l10n.soundEventTyping,
  };
}

extension AppEventLabel on AppEvent {
  String label(AppLocalizations l10n) => switch (this) {
    AppEvent.userLoggedIn => l10n.appEventUserLoggedIn,
    AppEvent.userLoggedOut => l10n.appEventUserLoggedOut,
    AppEvent.userJoined => l10n.appEventUserJoined,
    AppEvent.userLeft => l10n.appEventUserLeft,
    AppEvent.userJoinedOther => l10n.appEventUserJoinedOther,
    AppEvent.userLeftOther => l10n.appEventUserLeftOther,
    AppEvent.channelMessage => l10n.appEventChannelMessage,
    AppEvent.channelMessageSent => l10n.appEventChannelMessageSent,
    AppEvent.privateMessage => l10n.appEventPrivateMessage,
    AppEvent.broadcastMessage => l10n.appEventBroadcastMessage,
    AppEvent.filesUpdated => l10n.appEventFilesUpdated,
    AppEvent.voiceTransmitOn => l10n.appEventTransmitOn,
    AppEvent.voiceTransmitOff => l10n.appEventTransmitOff,
    AppEvent.voiceActivationEnabled => l10n.appEventVoxEnabled,
    AppEvent.voiceActivationDisabled => l10n.appEventVoxDisabled,
    AppEvent.voiceActivationTriggered => l10n.appEventVoxTriggered,
    AppEvent.voiceActivationReleased => l10n.appEventVoxReleased,
    AppEvent.connectionLost => l10n.eventConnectionLost,
    AppEvent.kickedFromServer => l10n.eventKickedFromServer,
    AppEvent.kickedFromChannel => l10n.eventKickedFromChannel,
  };
}

String sortLabel<F>(
  AppLocalizations l10n,
  SortState<F> sort,
  String Function(F) labelOf,
) => l10n.sortLabel(
  labelOf(sort.field),
  sort.ascending ? l10n.sortAscending : l10n.sortDescending,
);

extension ChatTemplateLabel on ChatTemplate {
  String label(AppLocalizations l10n) => switch (this) {
    ChatTemplate.channelMessage => l10n.chatTplLabelChannel,
    ChatTemplate.broadcastMessage => l10n.chatTplLabelBroadcast,
    ChatTemplate.privateMessage => l10n.chatTplLabelPrivate,
    ChatTemplate.logMessage => l10n.chatTplLabelLog,
    ChatTemplate.serverName => l10n.chatTplLabelServerName,
    ChatTemplate.serverMotd => l10n.chatTplLabelMotd,
    ChatTemplate.joinedChannel => l10n.chatTplLabelJoined,
    ChatTemplate.channelTopic => l10n.chatTplLabelTopic,
    ChatTemplate.channelQuota => l10n.chatTplLabelQuota,
  };

  Map<String, String> variableDescriptions(AppLocalizations l10n) => {
    for (final token in variables)
      token: switch (token) {
        '{date}' => isMessage ? l10n.varMessageDate : l10n.varDate,
        '{user}' => l10n.varSender,
        '{content}' => l10n.varContent,
        '{server}' => l10n.varServerName,
        '{MOTD}' => l10n.varMotd,
        '{channelpath}' => l10n.varChannelPath,
        '{channelname}' => l10n.varChannelName,
        '{channeltopic}' => l10n.varChannelTopic,
        '{quota}' => l10n.varQuota,
        _ => '',
      },
  };
}

Map<String, String> timestampVariableDescriptions(AppLocalizations l10n) => {
  for (final token in timestampVariables)
    token: switch (token) {
      '{year}' => l10n.tsYear,
      '{month}' => l10n.tsMonth,
      '{day}' => l10n.tsDay,
      '{hour}' => l10n.tsHour,
      '{hour12}' => l10n.tsHour12,
      '{minute}' => l10n.tsMinute,
      '{second}' => l10n.tsSecond,
      '{ampm}' => l10n.tsAmPm,
      _ => '',
    },
};

extension ServerLogEventLabel on ServerLogEvent {
  String label(AppLocalizations l10n) => switch (this) {
    ServerLogEvent.userConnected => l10n.logUserConnected,
    ServerLogEvent.userDisconnected => l10n.logUserDisconnected,
    ServerLogEvent.userLoggedIn => l10n.logUserLoggedIn,
    ServerLogEvent.userLoggedOut => l10n.logUserLoggedOut,
    ServerLogEvent.userLoginFailed => l10n.logUserLoginFailed,
    ServerLogEvent.userTimedOut => l10n.logUserTimedOut,
    ServerLogEvent.userKicked => l10n.logUserKicked,
    ServerLogEvent.userBanned => l10n.logUserBanned,
    ServerLogEvent.userUnbanned => l10n.logUserUnbanned,
    ServerLogEvent.userUpdated => l10n.logUserUpdated,
    ServerLogEvent.userJoinedChannel => l10n.logUserJoinedChannel,
    ServerLogEvent.userLeftChannel => l10n.logUserLeftChannel,
    ServerLogEvent.userMoved => l10n.logUserMoved,
    ServerLogEvent.userTextMessagePrivate => l10n.logUserTextPrivate,
    ServerLogEvent.userTextMessageCustom => l10n.logUserTextCustom,
    ServerLogEvent.userTextMessageChannel => l10n.logUserTextChannel,
    ServerLogEvent.userTextMessageBroadcast => l10n.logUserTextBroadcast,
    ServerLogEvent.channelCreated => l10n.logChannelCreated,
    ServerLogEvent.channelUpdated => l10n.logChannelUpdated,
    ServerLogEvent.channelRemoved => l10n.logChannelRemoved,
    ServerLogEvent.fileUploaded => l10n.logFileUploaded,
    ServerLogEvent.fileDownloaded => l10n.logFileDownloaded,
    ServerLogEvent.fileDeleted => l10n.logFileDeleted,
    ServerLogEvent.serverUpdated => l10n.logServerUpdated,
    ServerLogEvent.serverSaveConfig => l10n.logServerSaveConfig,
    ServerLogEvent.userCryptError => l10n.logUserCryptError,
    ServerLogEvent.userNewStream => l10n.logUserNewStream,
  };
}

extension MediaKeyLabel on MediaKey {
  String label(AppLocalizations l10n) => switch (this) {
    MediaKey.playPause => l10n.mediaKeyPlayPause,
    MediaKey.next => l10n.mediaKeyNext,
    MediaKey.previous => l10n.mediaKeyPrevious,
    MediaKey.fastForward => l10n.mediaKeyFastForward,
    MediaKey.rewind => l10n.mediaKeyRewind,
    MediaKey.stop => l10n.mediaKeyStop,
  };
}

extension KeyPressLabel on KeyPress {
  String label(AppLocalizations l10n) => switch (this) {
    KeyPress.single => l10n.keyPressSingle,
    KeyPress.long => l10n.keyPressLong,
  };
}

extension KeyActionLabel on KeyAction {
  String label(AppLocalizations l10n) => switch (this) {
    KeyAction.toggleTransmission => l10n.keyActionToggleTransmission,
    KeyAction.holdToTalk => l10n.keyActionHoldToTalk,
    KeyAction.toggleVoiceActivation => l10n.keyActionToggleVoiceActivation,
    KeyAction.toggleSpeakers => l10n.keyActionToggleSpeakers,
    KeyAction.toggleMicrophone => l10n.keyActionToggleMicrophone,
    KeyAction.nextChannel => l10n.keyActionNextChannel,
    KeyAction.previousChannel => l10n.keyActionPreviousChannel,
    KeyAction.joinSelectedChannel => l10n.keyActionJoinSelectedChannel,
    KeyAction.speakTalking => l10n.keyActionSpeakTalking,
    KeyAction.speakChannel => l10n.keyActionSpeakChannel,
    KeyAction.toggleRecording => l10n.keyActionToggleRecording,
  };
}

extension AppPermissionLabel on AppPermission {
  String label(AppLocalizations l10n) => switch (this) {
    AppPermission.microphone => l10n.permissionMicrophone,
    AppPermission.notifications => l10n.permissionNotifications,
    AppPermission.phone => l10n.permissionPhone,
    AppPermission.bluetooth => l10n.permissionBluetooth,
    AppPermission.battery => l10n.permissionBattery,
  };

  String reason(AppLocalizations l10n) => switch (this) {
    AppPermission.microphone => l10n.permissionMicrophoneWhy,
    AppPermission.notifications => l10n.permissionNotificationsWhy,
    AppPermission.phone => l10n.permissionPhoneWhy,
    AppPermission.bluetooth => l10n.permissionBluetoothWhy,
    AppPermission.battery => l10n.permissionBatteryWhy,
  };
}

extension AppThemeLabel on AppTheme {
  String label(AppLocalizations l10n) => switch (this) {
    AppTheme.system => l10n.themeSystem,
    AppTheme.light => l10n.themeLight,
    AppTheme.dark => l10n.themeDark,
  };
}
