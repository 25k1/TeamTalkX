import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/app_info.dart';
import 'src/app/app_startup.dart';
import 'src/app/security/secrets.dart';
import 'src/app/settings/settings_providers.dart';
import 'src/app/third_party_licenses.dart';
import 'src/diagnostics/diagnostics.dart';
import 'src/diagnostics/log.dart';
import 'src/platform/native_app_info.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  final (logFile, prefs, version, secrets) = await (
    initDiagnostics(),
    SharedPreferences.getInstance(),
    loadAppVersion(),
    openSecretStore(),
  ).wait;
  appLog.i('app', 'Starting $appClientName $version');
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appVersionProvider.overrideWithValue(version),
      logFileSinkProvider.overrideWithValue(logFile),
      secretStoreProvider.overrideWithValue(secrets),
    ],
  );
  startAppServices(container);
  runApp(
    UncontrolledProviderScope(container: container, child: const TeamTalkApp()),
  );
}
