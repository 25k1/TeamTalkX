import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/protocol/channel_wire.dart';
import 'package:teamtalkx/src/ui/channels/channel_edit_screen.dart';

import 'support/localized_app.dart';

class _FakeClient implements TeamTalkClient {
  _FakeClient(this.config);

  final TtChannelConfig config;
  TtChannelConfig? saved;

  @override
  ServerState get state => ServerState();
  @override
  Stream<TtEvent> get events => const Stream.empty();
  @override
  int get serverMaxUsers => 1000;
  @override
  TtChannelConfig getChannelConfig(int channelId) => config;
  @override
  Future<void> saveChannel(
    TtChannelConfig cfg, {
    int? parentId,
    int? channelId,
  }) async => saved = cfg;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('saving an untouched form keeps every channel property', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 20000);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const config = TtChannelConfig(
      name: 'Room',
      topic: 'Hi',
      password: 'secret',
      opPassword: 'opsecret',
      maxUsers: 25,
      diskQuotaKB: 10240,
      permanent: true,
      noRecording: true,
      gainLevel: 6000,
      codec: TtAudioCodec(opusApplication: 2051, opusBitrate: 32500),
    );
    final client = _FakeClient(config);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamTalkClientProvider.overrideWith((ref) => client),
        ],
        child: const LocalizedTestApp(
          home: ChannelEditScreen.edit(channelId: 2),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = client.saved!;
    expect(channelWireProperties(saved), channelWireProperties(config));
  });
}
