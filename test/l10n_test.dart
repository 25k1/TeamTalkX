import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/failures.dart';
import 'package:teamtalkx/src/app/settings/locale_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/l10n/failure_messages.dart';
import 'package:teamtalkx/src/l10n/l10n.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';
import 'package:teamtalkx/src/ui/common/failure_report.dart';
import 'package:teamtalkx/src/ui/settings/settings_screen.dart';

import 'support/fake_platform.dart';
import 'support/localized_app.dart';

const _locales = [Locale('en'), Locale('ru'), Locale('ka')];

void main() {
  group('failureFrom', () {
    test('maps server errors by TeamTalk code', () {
      final failure = failureFrom(TtCommandError(2001, 'Incorrect password'));

      expect(
        failure,
        isA<ServerRejected>().having(
          (f) => f.error,
          'error',
          ServerError.incorrectChannelPassword,
        ),
      );
    });

    test('keeps the server text for codes it does not know', () {
      final failure = failureFrom(TtCommandError(4242, 'Custom refusal'));

      expect(
        failure,
        isA<ServerRejected>()
            .having((f) => f.error, 'error', ServerError.other)
            .having((f) => f.serverMessage, 'message', 'Custom refusal'),
      );
    });

    test('maps network, storage and unknown errors', () {
      expect(
        failureFrom(const SocketException('refused')),
        isA<ServerUnreachable>(),
      );
      expect(failureFrom(TimeoutException('slow')), isA<ConnectionTimedOut>());
      expect(
        failureFrom(const TlsException('bad cert')),
        isA<SecureConnectionFailed>(),
      );
      expect(
        failureFrom(const FileSystemException('denied')),
        isA<StorageFailure>(),
      );
      expect(failureFrom(const NotConnected()), isA<NotConnected>());
      expect(failureFrom(StateError('bug')), isA<UnexpectedFailure>());
    });
  });

  test('server error codes match TeamTalk.h', () {
    expect(ServerError.fromCode(2002), ServerError.invalidAccount);
    expect(ServerError.fromCode(2006), ServerError.notAuthorized);
    expect(ServerError.fromCode(3005), ServerError.channelNotFound);
    expect(ServerError.fromCode(3017), ServerError.channelCannotBeHidden);
    expect(ServerError.fromCode(1), ServerError.other);
  });

  test('every failure has a message in every language', () {
    final failures = <TtFailure>[
      const ServerUnreachable(),
      const ConnectionTimedOut(),
      const SecureConnectionFailed(),
      const NotConnected(),
      const ServerClosedConnection(),
      const StorageFailure(),
      const WebServiceFailure(),
      const WebLoginRequired(),
      const UnexpectedFailure('x'),
      for (final error in ServerError.values)
        ServerRejected(error, serverMessage: 'server text'),
    ];
    for (final locale in _locales) {
      final l10n = lookupAppLocalizations(locale);
      for (final failure in failures) {
        expect(l10n.failureMessage(failure), isNotEmpty, reason: '$locale');
      }
      expect(
        l10n.failureMessage(
          const ServerRejected(ServerError.other, serverMessage: 'server text'),
        ),
        contains('server text'),
      );
    }
  });

  test('the Russian and Georgian strings are translated', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final locale in const [Locale('ru'), Locale('ka')]) {
      final other = lookupAppLocalizations(locale);
      expect(
        other.failureServerUnreachable,
        isNot(en.failureServerUnreachable),
      );
      expect(other.serverListTitle, isNot(en.serverListTitle));
    }
  });

  group('resolveAppLocale', () {
    test('a chosen language wins over the device', () {
      expect(resolveAppLocale('ka', const [Locale('ru')]), const Locale('ka'));
    });

    test('the first supported device language is used', () {
      expect(
        resolveAppLocale(null, const [Locale('de'), Locale('ru', 'RU')]),
        const Locale('ru'),
      );
    });

    test('English is the fallback', () {
      expect(resolveAppLocale(null, const [Locale('de')]), const Locale('en'));
    });
  });

  Future<ProviderContainer> container(
    Map<String, Object> prefs, {
    List<Locale> device = const [Locale('en')],
    FakePlatform? platform,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        deviceLocalesProvider.overrideWithValue(device),
        ...?platform?.overrides,
      ],
    );
  }

  testWidgets('choosing a language switches the UI and is saved', (
    tester,
  ) async {
    final c = await container({});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const LocalizedTestApp(home: SettingsScreen()),
      ),
    );
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Русский').last);
    await tester.pumpAndSettle();

    expect(find.text('Язык'), findsOneWidget);
    expect(
      c.read(sharedPreferencesProvider).getString('app_language'),
      'russian',
    );
    expect(c.read(appLocalizationsProvider).languageSetting, 'Язык');
  });

  testWidgets('a failure is shown and spoken in the app language', (
    tester,
  ) async {
    final platform = FakePlatform();
    addTearDown(platform.dispose);
    final c = await container({
      'app_language': 'russian',
      'speech_output': 'tts',
    }, platform: platform);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => reportFailure(
                  ref,
                  ScaffoldMessenger.of(context),
                  action: (l) => l.actionSave,
                  error: TtCommandError(2001, 'Incorrect channel password'),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();

    const expected = 'Не удалось сохранить: Неверный пароль канала.';
    expect(find.text(expected), findsOneWidget);
    expect(platform.tts.spoken, [expected]);
  });
}
