import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/settings/sound_player.dart';
import 'package:teamtalkx/src/audio/sound_effects.dart';

void _neverAnswers(SendPort _) {}

void main() {
  test('an event sound isolate that never answers times out', () async {
    final watch = Stopwatch()..start();
    await expectLater(
      SoundEffects.spawn(
        timeout: const Duration(milliseconds: 200),
        entryPoint: _neverAnswers,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  group('when event sounds fail to start', () {
    late ProviderContainer c;
    late File sound;
    late SoundPlayer soundPlayer;
    var spawns = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final shared = await SharedPreferences.getInstance();
      spawns = 0;
      final player = Provider<SoundPlayer>(
        (ref) => SoundPlayer(
          ref,
          spawn: () async {
            spawns++;
            throw TimeoutException('no answer');
          },
        ),
      );
      c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(shared)],
      );
      final dir = await Directory.systemTemp.createTemp('ttx-sound');
      sound = File('${dir.path}/beep.wav')..writeAsBytesSync([0]);
      addTearDown(() {
        c.dispose();
        dir.deleteSync(recursive: true);
      });
      soundPlayer = c.read(player);
    });

    test('playing a sound neither throws nor hangs', () async {
      await soundPlayer.playFile(sound.path);
      expect(spawns, 1);
    });

    test('the next sound tries to start them again', () async {
      await soundPlayer.playFile(sound.path);
      await soundPlayer.playFile(sound.path);
      expect(spawns, 2);
    });

    test('changing the output meanwhile is harmless', () async {
      await soundPlayer.playFile(sound.path);
      soundPlayer.setOutput(voiceCall: true);
      await pumpEventQueue();
      expect(spawns, 1);
    });
  });
}
