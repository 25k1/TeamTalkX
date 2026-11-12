import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/channels/channel_tree_providers.dart';
import 'package:teamtalkx/src/app/chat/chat_providers.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/files/file_providers.dart';
import 'package:teamtalkx/src/app/files/sort.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/l10n/l10n.dart';
import 'package:teamtalkx/src/ui/channels/channel_info_screen.dart';
import 'package:teamtalkx/src/ui/common/labels.dart';

import 'support/localized_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ru = lookupAppLocalizations(const Locale('ru'));
final _ka = lookupAppLocalizations(const Locale('ka'));

class _FakeClient implements TeamTalkClient {
  final eventController = StreamController<TtEvent>.broadcast();

  @override
  final ServerState state = ServerState();
  @override
  Stream<TtEvent> get events => eventController.stream;
  @override
  String channelPath(int channelId) => '/Room/';
  Future<void> close() => eventController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _container(
  _FakeClient client, {
  String language = 'russian',
}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      teamTalkClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('sort and status labels exist in every language', () {
    for (final l10n in [_en, _ru, _ka]) {
      for (final s in ChannelSort.values) {
        expect(s.label(l10n), isNotEmpty);
      }
      for (final f in FileSortField.values) {
        expect(f.label(l10n), isNotEmpty);
      }
      for (final s in UserStatus.values) {
        expect(s.label(l10n), isNotEmpty);
      }
    }
    expect(
      ChannelSort.popularity.label(_ru),
      isNot(ChannelSort.popularity.label(_en)),
    );
  });

  test('the sort button label names field and direction', () {
    const sort = SortState(FileSortField.size, ascending: false);

    expect(
      sortLabel(_en, sort, (f) => f.label(_en)),
      'Sort by Size descending',
    );
    expect(
      sortLabel(_ru, sort, (f) => f.label(_ru)),
      'Сортировка: По размеру, по убыванию',
    );
  });

  test('file sizes are localized, with Russian plurals', () {
    expect(localizedFileSize(_en, 938), '938 bytes');
    expect(localizedFileSize(_en, 1), '1 byte');
    expect(localizedFileSize(_en, 12 * 1024), '12 KB');
    expect(localizedFileSize(_ru, 1), '1 байт');
    expect(localizedFileSize(_ru, 3), '3 байта');
    expect(localizedFileSize(_ru, 5), '5 байт');
    expect(localizedFileSize(_ru, 3 * 1024 * 1024 ~/ 2), '1.5 МБ');
    expect(localizedFileSize(_ka, 5), '5 ბაიტი');
  });

  testWidgets('channel information is shown in the app language', (
    tester,
  ) async {
    final client = _FakeClient();
    addTearDown(client.close);
    client.state.apply(
      const ChannelNewEvent(
        TtChannel(
          id: 2,
          parentId: 1,
          name: 'Room',
          topic: '',
          hasPassword: true,
          maxUsers: 10,
          channelType: ChannelTypes.permanent | ChannelTypes.hidden,
        ),
      ),
    );
    final c = await _container(client);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const LocalizedTestApp(home: ChannelInfoScreen(channelId: 2)),
      ),
    );

    expect(find.text('Сведения о канале'), findsOneWidget);
    expect(find.text('Защищён паролем'), findsOneWidget);
    expect(find.text('Да'), findsOneWidget);
    expect(find.text('Постоянный, Скрытый'), findsOneWidget);
    expect(find.text('0 из 10'), findsOneWidget);
  });

  test('the chat log is written in the app language', () async {
    final client = _FakeClient();
    addTearDown(client.close);
    final c = await _container(client, language: 'georgian');
    c.read(chatProvider);

    client.eventController
      ..add(const ConSuccessEvent())
      ..add(const ConLostEvent());
    await pumpEventQueue();

    expect(c.read(chatProvider).map((e) => e.text), [
      _ka.chatLogConnected,
      _ka.chatLogConnectionLost,
    ]);
  });
}
