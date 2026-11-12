import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/announcer.dart';
import '../app/chat/pm_notification_routing.dart';
import '../app/files/file_providers.dart';
import '../app/platform_services.dart';
import '../app/settings/first_run.dart';
import '../app/settings/locale_providers.dart';
import '../app/settings/settings_providers.dart';
import '../l10n/l10n.dart';
import 'chat/pm_screen.dart';
import 'first_run/first_run_screen.dart';
import 'servers/server_list_screen.dart';

class TeamTalkApp extends ConsumerStatefulWidget {
  const TeamTalkApp({super.key});

  @override
  ConsumerState<TeamTalkApp> createState() => _TeamTalkAppState();
}

class _TeamTalkAppState extends ConsumerState<TeamTalkApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<int>? _pmOpenSub;
  StreamSubscription<SavedDownload>? _savedSub;

  @override
  void initState() {
    super.initState();
    _pmOpenSub = ref.read(pmOpenRequestsProvider).listen(_openPm);
    _savedSub = ref
        .read(fileTransfersProvider.notifier)
        .saved
        .listen(_offerToOpen);
  }

  void _offerToOpen(SavedDownload download) {
    final messenger = _messengerKey.currentState;
    final context = _navigatorKey.currentContext;
    if (messenger == null || context == null) return;
    final l10n = context.l10n;
    final text = l10n.transferSaved(download.name, download.path);
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.transferOpenFile,
          onPressed: () => unawaited(_open(download)),
        ),
      ),
    );
    ref.read(announcerProvider).announceShown(text);
  }

  Future<void> _open(SavedDownload download) async {
    final opened = await ref.read(downloadsProvider).open(download.uri);
    if (!opened) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(ref.read(appLocalizationsProvider).filesNoAppToOpen),
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_pmOpenSub?.cancel());
    unawaited(_savedSub?.cancel());
    super.dispose();
  }

  void _openPm(int userId) {
    void push() => _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => PmScreen(userId: userId)),
    );
    if (_navigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => push());
    } else {
      push();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ttsConfiguratorProvider);
    final settings = ref.watch(
      settingsProvider.select(
        (s) => (theme: s.theme, highContrast: s.highContrast),
      ),
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      onGenerateTitle: (context) => context.l10n.appTitle,
      locale: ref.watch(appLocaleProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: switch (settings.theme) {
        AppTheme.system => ThemeMode.system,
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
      },
      theme: appTheme(Brightness.light, highContrast: settings.highContrast),
      darkTheme: appTheme(Brightness.dark, highContrast: settings.highContrast),
      home: ref.watch(firstRunProvider)
          ? const FirstRunScreen()
          : const ServerListScreen(),
    );
  }
}

ThemeData appTheme(Brightness brightness, {required bool highContrast}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
    contrastLevel: highContrast ? 1.0 : 0.0,
  );
  if (!highContrast) return ThemeData(colorScheme: scheme);
  final outline = BorderSide(color: scheme.onSurface, width: 2);
  return ThemeData(
    colorScheme: scheme,
    dividerTheme: DividerThemeData(color: scheme.onSurface, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderSide: outline),
      enabledBorder: OutlineInputBorder(borderSide: outline),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(side: outline),
    ),
  );
}
