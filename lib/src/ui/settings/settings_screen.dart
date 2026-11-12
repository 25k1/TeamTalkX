import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/platform_services.dart';
import '../../app/servers/bearware_login.dart';
import '../../app/settings/settings_providers.dart';
import '../../domain/app_permission.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../chat/chat_templates_screen.dart';
import '../common/command_runner.dart';
import '../common/labels.dart';
import '../common/ui.dart';
import '../connection/nickname_action.dart';
import '../first_run/first_run_screen.dart';
import '../security/trusted_certificates_screen.dart';
import '../servers/bearware_login_screen.dart';
import '../updates/updates_screen.dart';
import '../users/remembered_users_screen.dart';
import '../voice/audio_settings_screen.dart';
import '../voice/voice_activation_screen.dart';
import 'calls_settings_screen.dart';
import 'chat_history_screen.dart';
import 'diagnostics_settings.dart';
import 'events_screen.dart';
import 'media_keys_screen.dart';
import 'recording_settings.dart';
import 'settings_file_actions.dart';
import 'settings_search.dart';
import 'settings_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

List<SettingsSection> settingsSections() => [
  SettingsSection(
    title: (l) => l.settingsGeneral,
    subtitle: (l) => l.settingsGeneralSub,
    icon: Icons.settings,
    builder: (_) => const _GeneralTab(),
  ),
  SettingsSection(
    title: (l) => l.settingsAudio,
    subtitle: (l) => l.settingsAudioSub,
    icon: Icons.volume_up,
    screen: (_) => const AudioSettingsScreen(),
  ),
  SettingsSection(
    title: (l) => l.settingsVoiceActivation,
    subtitle: (l) => l.settingsVoiceActivationSub,
    icon: Icons.record_voice_over,
    screen: (_) => const VoiceActivationScreen(),
  ),
  SettingsSection(
    title: (l) => l.settingsKeys,
    subtitle: (l) => l.settingsKeysSub,
    icon: Icons.keyboard,
    builder: (_) => const _KeysTab(),
  ),
  SettingsSection(
    title: (l) => l.settingsCalls,
    subtitle: (l) => l.settingsCallsSub,
    icon: Icons.phone_in_talk,
    screen: (_) => const CallsSettingsScreen(),
  ),
  SettingsSection(
    title: (l) => l.settingsEvents,
    subtitle: (l) => l.settingsEventsSub,
    icon: Icons.notifications_active,
    builder: (_) => const EventsScreen(),
  ),
  SettingsSection(
    title: (l) => l.settingsChat,
    subtitle: (l) => l.settingsChatSub,
    icon: Icons.chat,
    builder: (_) => const _ChatTab(),
  ),
  SettingsSection(
    title: (l) => l.settingsRecording,
    subtitle: (l) => l.settingsRecordingSub,
    icon: Icons.fiber_manual_record,
    builder: (_) => const RecordingSettingsView(),
  ),
  SettingsSection(
    title: (l) => l.settingsServerList,
    subtitle: (l) => l.settingsServerListSub,
    icon: Icons.dns,
    builder: (_) => const _ServerListTab(),
  ),
  SettingsSection(
    title: (l) => l.settingsPrivacy,
    subtitle: (l) => l.settingsPrivacySub,
    icon: Icons.privacy_tip,
    builder: (_) => const DiagnosticsSettings(),
  ),
  SettingsSection(
    title: (l) => l.settingsUpdates,
    subtitle: (l) => l.settingsUpdatesSub,
    icon: Icons.system_update,
    builder: (_) => const UpdatesView(),
  ),
  SettingsSection(
    title: (l) => l.settingsAbout,
    subtitle: (l) => l.settingsAboutSub,
    icon: Icons.info_outline,
    builder: (_) => const _AboutTab(),
  ),
];

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();
    final results = query.isEmpty
        ? const <SettingsSearchEntry>[]
        : [
            for (final entry in settingsIndex(l10n))
              if (entry.matches(query)) entry,
          ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.commonSettings)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: l10n.settingsSearch,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: l10n.commonClearSearch,
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? ListView(
                    children: [
                      for (final section in settingsSections())
                        _SectionTile(section: section),
                    ],
                  )
                : results.isEmpty
                ? Center(child: Text(l10n.settingsSearchNone))
                : ListView(
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: ListTile(
                          dense: true,
                          title: Text(
                            l10n.settingsSearchResults(results.length),
                          ),
                        ),
                      ),
                      for (final entry in results)
                        ListTile(
                          title: Text(entry.title),
                          subtitle: Text(entry.path),
                          onTap: () => entry.open(context),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = section.title(l10n);
    final subtitle = section.subtitle(l10n);
    void open() => section.open(context);
    return Semantics(
      label: l10n.settingsSectionLabel(title, subtitle),
      onTap: open,
      excludeSemantics: true,
      child: ListTile(
        leading: Icon(section.icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: open,
      ),
    );
  }
}

class SettingsSection {
  const SettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.builder,
    this.screen,
  }) : assert((builder == null) != (screen == null));

  final L10nText title;
  final L10nText subtitle;
  final IconData icon;

  final WidgetBuilder? builder;

  final WidgetBuilder? screen;

  void open(BuildContext context) {
    final screen = this.screen;
    if (screen != null) {
      pushScreen(context, Builder(builder: screen));
      return;
    }
    pushScreen(
      context,
      Scaffold(
        appBar: AppBar(title: Text(title(context.l10n))),
        body: Builder(builder: builder!),
      ),
    );
  }
}

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(bearwareAccountProvider);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    String languageName(AppLanguage language) => switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.english => 'English',
      AppLanguage.russian => 'Русский',
      AppLanguage.georgian => 'ქართული',
    };
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.languageSetting),
          subtitle: Text(languageName(settings.language)),
          onTap: () async {
            final language = await showSingleChoiceMenu<AppLanguage>(
              context,
              title: l10n.languageSetting,
              options: {
                for (final language in AppLanguage.values)
                  language: languageName(language),
              },
              selected: settings.language,
            );
            if (language != null) notifier.setLanguage(language);
          },
        ),
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: Text(l10n.settingsTheme),
          subtitle: Text(settings.theme.label(l10n)),
          onTap: () async {
            final theme = await showSingleChoiceMenu<AppTheme>(
              context,
              title: l10n.settingsTheme,
              options: {for (final t in AppTheme.values) t: t.label(l10n)},
              selected: settings.theme,
            );
            if (theme != null) notifier.setTheme(theme);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.contrast),
          title: Text(l10n.settingsHighContrast),
          subtitle: Text(l10n.settingsHighContrastSub),
          value: settings.highContrast,
          onChanged: notifier.setHighContrast,
        ),
        SectionHeader(l10n.settingsAccount),
        ListTile(
          leading: const Icon(Icons.badge),
          title: Text(l10n.commonNickname),
          subtitle: Text(
            settings.nickname.isEmpty ? l10n.settingsNotSet : settings.nickname,
          ),
          onTap: () => editNickname(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.account_circle),
          title: Text(l10n.bearwareTitle),
          subtitle: Text(
            account.isLinked
                ? l10n.bearwareLinkedAs(account.username)
                : l10n.settingsNotLinked,
          ),
          onTap: () => pushScreen(context, const BearwareLoginScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.people_alt),
          title: Text(l10n.settingsRememberedUsers),
          subtitle: Text(l10n.settingsRememberedUsersSub),
          onTap: () => pushScreen(context, const RememberedUsersScreen()),
        ),
        SectionHeader(l10n.settingsProfile),
        ListTile(
          leading: const Icon(Icons.wc),
          title: Text(l10n.settingsGender),
          subtitle: Text(settings.gender.label(l10n)),
          onTap: () async {
            final gender = await showSingleChoiceMenu<Gender>(
              context,
              title: l10n.settingsGender,
              options: {for (final g in Gender.values) g: g.label(l10n)},
              selected: settings.gender,
            );
            if (gender == null) return;
            notifier.setGender(gender);
            final client = ref.read(teamTalkClientProvider);
            final me = client.state.users[client.state.myUserId];
            if (me != null) {
              client
                  .changeStatus(
                    (me.statusMode & ~TtStatusMode.genderMask) |
                        gender.statusBits,
                    me.statusMessage,
                  )
                  .ignore();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.assistant),
          title: Text(l10n.setupRunAgain),
          subtitle: Text(l10n.setupRunAgainSub),
          onTap: () => FirstRunScreen.open(context),
        ),
        const _BatteryTile(),
        SectionHeader(l10n.settingsFile),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: Text(l10n.settingsFileExport),
          subtitle: Text(l10n.settingsFileExportSub),
          onTap: () => exportSettingsFile(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: Text(l10n.settingsFileImport),
          subtitle: Text(l10n.settingsFileImportSub),
          onTap: () => importSettingsFile(context, ref),
        ),
        SectionHeader(l10n.settingsConnection),
        SwitchListTile(
          secondary: const Icon(Icons.account_tree),
          title: Text(l10n.settingsAutoJoinRoot),
          subtitle: Text(l10n.settingsAutoJoinRootSub),
          value: settings.autoJoinRootChannel,
          onChanged: notifier.setAutoJoinRootChannel,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.power_settings_new),
          title: Text(l10n.settingsKeepAwake),
          subtitle: Text(l10n.settingsKeepAwakeSub),
          value: settings.keepAwakeWhileConnected,
          onChanged: notifier.setKeepAwakeWhileConnected,
        ),
      ],
    );
  }
}

class _BatteryTile extends ConsumerStatefulWidget {
  const _BatteryTile();

  @override
  ConsumerState<_BatteryTile> createState() => _BatteryTileState();
}

class _BatteryTileState extends ConsumerState<_BatteryTile> {
  bool? _exempt;

  @override
  void initState() {
    super.initState();
    _check();
  }

  void _check() {
    ref.read(permissionsProvider).isGranted(AppPermission.battery).then((v) {
      if (mounted) setState(() => _exempt = v);
    }).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: const Icon(Icons.battery_saver),
      title: Text(l10n.permissionBattery),
      subtitle: Text(
        _exempt ?? false ? l10n.setupAllowed : l10n.permissionBatteryWhy,
      ),
      onTap: () async {
        await ref.read(permissionsProvider).request(AppPermission.battery);
        _check();
      },
    );
  }
}

Future<void> _mapPttHotkey(BuildContext context, WidgetRef ref) async {
  final hotkey = ref.read(hotkeysProvider);
  final notifier = ref.read(settingsProvider.notifier);
  final navigator = Navigator.of(context);
  var handled = false;
  final sub = hotkey.captured.listen((event) {
    if (handled) return;
    handled = true;
    final (keyCode, label) = event;
    notifier.setPttKey(keyCode, label);
    navigator.pop();
  });
  hotkey.startCapture().ignore();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.settingsPttMapTitle),
      content: Text(context.l10n.settingsPttMapBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
      ],
    ),
  );
  await sub.cancel();
  await hotkey.stopCapture();
}

class _ServerListTab extends ConsumerWidget {
  const _ServerListTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return ListView(
      children: [
        SwitchListTile(
          title: Text(context.l10n.settingsShowOfficial),
          subtitle: Text(context.l10n.settingsShowOfficialSub),
          value: settings.showOfficialServers,
          onChanged: notifier.setShowOfficialServers,
        ),
        SwitchListTile(
          title: Text(context.l10n.settingsShowUnofficial),
          subtitle: Text(context.l10n.settingsShowUnofficialSub),
          value: settings.showUnofficialServers,
          onChanged: notifier.setShowUnofficialServers,
        ),
        ListTile(
          leading: const Icon(Icons.lock),
          title: Text(context.l10n.certificatesTitle),
          subtitle: Text(context.l10n.certificatesSub),
          onTap: () => pushScreen(context, const TrustedCertificatesScreen()),
        ),
      ],
    );
  }
}

class _KeysTab extends ConsumerWidget {
  const _KeysTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: Text(l10n.settingsPttKey),
          subtitle: Text(
            settings.pttKeyLabel.isEmpty
                ? l10n.settingsPttKeyNone
                : l10n.settingsPttKeyHold(settings.pttKeyLabel),
          ),
          onTap: () => _mapPttHotkey(context, ref),
          trailing: settings.pttKeyCode == 0
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: l10n.settingsPttKeyClear,
                  onPressed: () => notifier.setPttKey(0, ''),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.headset),
          title: Text(l10n.settingsMediaKeys),
          subtitle: Text(l10n.settingsMediaKeysSub),
          onTap: () => pushScreen(context, const MediaKeysScreen()),
        ),
      ],
    );
  }
}

class _ChatTab extends StatelessWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(l10n.settingsChatHistory),
          subtitle: Text(l10n.settingsChatHistorySub),
          onTap: () => pushScreen(context, const ChatHistoryScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: Text(l10n.eventsEditChatTemplates),
          subtitle: Text(l10n.eventsEditChatTemplatesSub),
          onTap: () => pushScreen(context, const ChatTemplatesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(l10n.eventsEditTimestamp),
          subtitle: Text(l10n.eventsEditTimestampSub('{date}')),
          onTap: () => pushScreen(context, const TimestampScreen()),
        ),
      ],
    );
  }
}

class _AboutTab extends ConsumerWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(appVersionProvider);
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appTitle),
          subtitle: Text(l10n.aboutVersion(version)),
        ),
        ListTile(
          leading: const Icon(Icons.description),
          title: Text(l10n.aboutLicenses),
          subtitle: Text(l10n.aboutLicensesSub),
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: version,
          ),
        ),
      ],
    );
  }
}
