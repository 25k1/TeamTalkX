import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/chat/chat_templates.dart';
import 'package:teamtalkx/src/app/settings/event_config.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/l10n/l10n.dart';
import 'package:teamtalkx/src/ui/common/labels.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _ru = lookupAppLocalizations(const Locale('ru'));
final _ka = lookupAppLocalizations(const Locale('ka'));

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(sharedPrefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('default event templates keep their tokens in every language', () {
    for (final l10n in [_en, _ru, _ka]) {
      for (final event in AppEvent.values) {
        final template = defaultEventTemplate(event, l10n);
        for (final token in RegExp(r'\{(\w+)\}').allMatches(template)) {
          expect(
            event.variables,
            contains(token.group(1)),
            reason: '${l10n.localeName} ${event.name}: $template',
          );
        }
      }
    }
    expect(
      defaultEventTemplate(AppEvent.userJoinedOther, _ru),
      '{nickname} входит в {channel}',
    );
  });

  test('an unedited event template follows the app language (D113)', () async {
    final c = await _container({'app_language': 'english'});
    final events = c.read(eventConfigProvider.notifier);
    expect(
      events.speechTemplate(AppEvent.userLoggedIn),
      '{nickname} logged on',
    );

    c.read(settingsProvider.notifier).setLanguage(AppLanguage.georgian);

    expect(
      events.speechTemplate(AppEvent.userLoggedIn),
      '{nickname} სერვერზე შემოვიდა',
    );
  });

  test('an edited template keeps the user text until reset', () async {
    final c = await _container({'app_language': 'english'});
    final events = c.read(eventConfigProvider.notifier)
      ..setTemplate(AppEvent.userLoggedIn, 'Hi {nickname}');

    c.read(settingsProvider.notifier).setLanguage(AppLanguage.russian);
    expect(events.speechTemplate(AppEvent.userLoggedIn), 'Hi {nickname}');

    events.resetTemplate(AppEvent.userLoggedIn);
    expect(
      events.speechTemplate(AppEvent.userLoggedIn),
      '{nickname} входит на сервер',
    );
    expect(
      c
          .read(sharedPreferencesProvider)
          .getString('event.userLoggedIn.template'),
      isNull,
    );
  });

  test('setting and event labels exist in every language', () {
    for (final l10n in [_en, _ru, _ka]) {
      for (final e in AppEvent.values) {
        expect(e.label(l10n), isNotEmpty);
      }
      for (final s in SoundEvent.values) {
        expect(s.label(l10n), isNotEmpty);
      }
      for (final g in Gender.values) {
        expect(g.label(l10n), isNotEmpty);
      }
      expect(l10n.valuePercent(5), contains('5'));
    }
    expect(_ru.valuePercent(1), '1 процент');
    expect(_ru.valuePercent(3), '3 процента');
    expect(_ru.valuePercent(25), '25 процентов');
  });

  test('chat templates follow the language until edited (D113)', () async {
    final c = await _container({'app_language': 'russian'});
    final templates = c.read(chatTemplatesProvider.notifier);
    expect(
      templates.format(ChatTemplate.broadcastMessage, {
        '{date}': '12:00',
        '{user}': 'Ana',
        '{content}': 'hi',
      }),
      '12:00 <Ana->РАССЫЛКА>\nhi',
    );

    templates.setTemplate(ChatTemplate.channelTopic, 'T: {channeltopic}');
    c.read(settingsProvider.notifier).setLanguage(AppLanguage.georgian);

    expect(templates.of(ChatTemplate.channelTopic), 'T: {channeltopic}');
    expect(templates.of(ChatTemplate.channelQuota), 'დისკის კვოტა: {quota}');

    templates.resetAll();
    expect(templates.of(ChatTemplate.channelTopic), 'თემა: {channeltopic}');
  });

  test('every chat template variable has a description', () {
    for (final l10n in [_en, _ru, _ka]) {
      for (final t in ChatTemplate.values) {
        expect(t.label(l10n), isNotEmpty);
        for (final description in t.variableDescriptions(l10n).values) {
          expect(
            description,
            isNotEmpty,
            reason: '${t.name} ${l10n.localeName}',
          );
        }
        for (final token in RegExp(
          r'\{\w+\}',
        ).allMatches(defaultChatTemplate(t, l10n))) {
          expect(t.variables, contains(token.group(0)));
        }
      }
      expect(
        timestampVariableDescriptions(l10n).values,
        everyElement(isNotEmpty),
      );
    }
  });
}
