import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs_notifier.dart';
import 'settings_types.dart';

class ProfileSettings {
  const ProfileSettings({
    this.nickname = '',
    this.status = UserStatus.available,
    this.statusMessage = '',
    this.gender = Gender.male,
  });

  final String nickname;
  final UserStatus status;
  final String statusMessage;
  final Gender gender;

  ProfileSettings copyWith({
    String? nickname,
    UserStatus? status,
    String? statusMessage,
    Gender? gender,
  }) => ProfileSettings(
    nickname: nickname ?? this.nickname,
    status: status ?? this.status,
    statusMessage: statusMessage ?? this.statusMessage,
    gender: gender ?? this.gender,
  );
}

final profileSettingsProvider =
    NotifierProvider<ProfileSettingsNotifier, ProfileSettings>(
      ProfileSettingsNotifier.new,
    );

class ProfileSettingsNotifier extends PrefsNotifier<ProfileSettings> {
  @override
  ProfileSettings build() => ProfileSettings(
    nickname: prefs.getString('nickname') ?? '',
    status: UserStatus.fromName(prefs.getString('status_mode')),
    statusMessage: prefs.getString('status_message') ?? '',
    gender: Gender.fromName(prefs.getString('gender')),
  );

  void setNickname(String v) =>
      saveString('nickname', v, (s) => s.copyWith(nickname: v));

  void setStatus(UserStatus status) =>
      saveString('status_mode', status.name, (s) => s.copyWith(status: status));

  void setStatusMessage(String v) =>
      saveString('status_message', v, (s) => s.copyWith(statusMessage: v));

  void setGender(Gender gender) =>
      saveString('gender', gender.name, (s) => s.copyWith(gender: gender));
}

class AppearanceSettings {
  const AppearanceSettings({
    this.language = AppLanguage.system,
    this.theme = AppTheme.system,
    this.highContrast = false,
  });

  final AppLanguage language;
  final AppTheme theme;
  final bool highContrast;

  AppearanceSettings copyWith({
    AppLanguage? language,
    AppTheme? theme,
    bool? highContrast,
  }) => AppearanceSettings(
    language: language ?? this.language,
    theme: theme ?? this.theme,
    highContrast: highContrast ?? this.highContrast,
  );
}

final appearanceSettingsProvider =
    NotifierProvider<AppearanceSettingsNotifier, AppearanceSettings>(
      AppearanceSettingsNotifier.new,
    );

class AppearanceSettingsNotifier extends PrefsNotifier<AppearanceSettings> {
  @override
  AppearanceSettings build() => AppearanceSettings(
    language: AppLanguage.fromName(prefs.getString('app_language')),
    theme: AppTheme.fromName(prefs.getString('theme')),
    highContrast: prefs.getBool('high_contrast') ?? false,
  );

  void setLanguage(AppLanguage language) => saveString(
    'app_language',
    language.name,
    (s) => s.copyWith(language: language),
  );

  void setTheme(AppTheme v) =>
      saveString('theme', v.name, (s) => s.copyWith(theme: v));

  void setHighContrast(bool v) =>
      saveBool('high_contrast', v, (s) => s.copyWith(highContrast: v));
}
