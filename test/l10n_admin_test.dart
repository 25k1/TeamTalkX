import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/l10n/failure_messages.dart';
import 'package:teamtalkx/src/l10n/l10n.dart';
import 'package:teamtalkx/src/ui/channels/channel_edit_screen.dart';
import 'package:teamtalkx/src/ui/common/async_list_view.dart';
import 'package:teamtalkx/src/ui/common/labels.dart';
import 'package:teamtalkx/src/ui/users/remembered_users_screen.dart';

import 'support/localized_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ru = lookupAppLocalizations(const Locale('ru'));
final _ka = lookupAppLocalizations(const Locale('ka'));

class _FakeClient implements TeamTalkClient {
  @override
  ServerState get state => ServerState();
  @override
  int get serverMaxUsers => 1000;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  Map<String, Object> prefs,
) async {
  tester.view.physicalSize = const Size(1080, 20000);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        teamTalkClientProvider.overrideWith((ref) => _FakeClient()),
      ],
      child: LocalizedTestApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the channel form follows the app language', (tester) async {
    await _pump(tester, const ChannelEditScreen.create(parentId: 1), {
      'app_language': 'russian',
    });

    expect(find.text(_ru.channelEditCreate), findsOneWidget);
    expect(find.text(_ru.channelEditName), findsOneWidget);
    expect(find.text(_ru.channelEditCodec), findsOneWidget);
    expect(find.text(_ru.channelTypePermanent), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('remembered users are summarized in the app language', (
    tester,
  ) async {
    final stored = jsonEncode({
      'example.org:10333': [
        {
          'username': '',
          'muted': true,
          'volume': 80,
          'subscriptions': Subscriptions.voice,
          'subscriptionsVersion': 2,
        },
      ],
    });
    await _pump(tester, const RememberedUsersScreen(), {
      'app_language': 'georgian',
      'user_configs': stored,
    });

    final summary = [
      _ka.commonMuted,
      _ka.rememberedVolume(80),
      _ka.rememberedSubVoice,
    ].join(', ');
    expect(find.text(_ka.rememberedNoUsername), findsOneWidget);
    expect(find.text(summary), findsOneWidget);
  });

  testWidgets('a list that failed to load explains why, localized', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AsyncListView<int>(
          loading: false,
          failure: const NotConnected(),
          items: const [],
          loadingLabel: '',
          errorPrefix: _ru.accountsLoadFailed,
          emptyMessage: '',
          itemBuilder: (_, _) => const SizedBox(),
        ),
      ),
    );

    expect(
      find.text(
        '${_ru.accountsLoadFailed}: ${_ru.failureMessage(const NotConnected())}',
      ),
      findsOneWidget,
    );
  });

  test('admin labels exist in every language', () {
    for (final l10n in [_en, _ru, _ka]) {
      for (final event in ServerLogEvent.values) {
        expect(event.label(l10n), isNotEmpty, reason: l10n.localeName);
      }
      expect(
        l10n.cmdLimitPerSeconds(10, 60),
        allOf(contains('10'), contains('60')),
      );
      expect(l10n.channelEditWideBand(l10n.unitKhz('16')), contains('16'));
    }
    expect(_en.rememberedImported(1), 'Imported 1 user setting');
    expect(_en.rememberedImported(3), 'Imported 3 user settings');
    expect(_ru.rememberedImported(5), 'Импортировано 5 настроек');
  });
}
