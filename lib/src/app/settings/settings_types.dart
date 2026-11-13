enum FocusLossPolicy {
  ignore,
  duck,
  mute;

  static FocusLossPolicy fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => ignore);
}

enum SoundEvent {
  userJoin('user_join.ogg'),
  userLeft('user_left.ogg'),
  loggedOn('logged_on.ogg'),
  loggedOff('logged_off.ogg'),
  channelMessage('channel_message.ogg'),
  channelMessageSent('channel_message_sent.ogg'),
  userMessage('user_message.ogg'),
  broadcastMessage('broadcast_message.ogg'),
  serverLost('serverlost.ogg'),
  txOn('tx_on.ogg'),
  txOff('tx_off.ogg'),
  voiceActEnable('voiceact_enable.ogg'),
  voiceActDisable('voiceact_disable.ogg'),
  voiceActOn('voiceact_on.ogg'),
  voiceActOff('voiceact_off.ogg'),
  fileUpdate('fileupdate.ogg'),
  typing('typing.ogg');

  const SoundEvent(this.asset);

  final String asset;

  String get packName => asset.substring(0, asset.lastIndexOf('.'));
}

enum AppLanguage {
  system(null),
  english('en'),
  russian('ru'),
  georgian('ka');

  const AppLanguage(this.code);

  final String? code;

  static AppLanguage fromName(String? name) => values.firstWhere(
    (l) => l.name == name,
    orElse: () => AppLanguage.system,
  );
}

enum VadEngine {
  rnnoise('RNNoise'),
  silero('Silero');

  const VadEngine(this.label);

  final String label;

  static VadEngine fromName(String? name) =>
      VadEngine.values.firstWhere((e) => e.name == name, orElse: () => rnnoise);
}

enum AppTheme {
  system,
  light,
  dark;

  static AppTheme fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => system);
}

enum SpeechOutput {
  screenReader,
  tts,
  none;

  static SpeechOutput fromName(String? name) => switch (name) {
    'tts' => SpeechOutput.tts,
    'none' => SpeechOutput.none,
    _ => SpeechOutput.screenReader,
  };
}

enum Gender {
  male(0x00000000),
  female(0x00000100),
  neutral(0x00001000);

  const Gender(this.statusBits);

  final int statusBits;

  static Gender fromName(String? name) =>
      Gender.values.firstWhere((g) => g.name == name, orElse: () => male);
}

enum UserStatus {
  available(0x00000000),
  away(0x00000001),
  question(0x00000002);

  const UserStatus(this.statusBits);

  final int statusBits;

  static UserStatus fromName(String? name) => UserStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => available,
  );

  static UserStatus fromMode(int mode) {
    if ((mode & question.statusBits) != 0) return question;
    if ((mode & away.statusBits) != 0) return away;
    return available;
  }
}

enum StereoChannel {
  both,
  left,
  right;

  static StereoChannel fromName(String? name) => StereoChannel.values
      .firstWhere((c) => c.name == name, orElse: () => StereoChannel.both);

  int get outputChannel => switch (this) {
    StereoChannel.both => -1,
    StereoChannel.left => 0,
    StereoChannel.right => 1,
  };
}
