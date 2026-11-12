import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/mic_test.dart';
import 'package:teamtalkx/src/app/voice/voice_providers.dart';
import 'package:teamtalkx/src/audio/mic_test.dart';
import 'package:teamtalkx/src/domain/audio_output.dart';

Uint8List _frame({int channels = 1, int left = 1000, int right = 3000}) {
  final b = ByteData(320 * channels * 2);
  for (var f = 0; f < 320; f++) {
    b.setInt16(f * channels * 2, left, Endian.little);
    if (channels == 2) b.setInt16(f * 4 + 2, right, Endian.little);
  }
  return b.buffer.asUint8List();
}

class _Voice extends VoiceNotifier {
  _Voice(this._state);
  final VoiceState _state;
  @override
  VoiceState build() => _state;
}

void main() {
  group('the recorder (D71)', () {
    test('live: each frame comes back at 48 kHz stereo, at its gain', () {
      final r = MicTestRecorder(live: true, sampleRate: 16000, channels: 1);
      final out = r.add(_frame(), 2)!;
      expect(out.length, closeTo(960 * 2, 6));
      expect(out.sublist(10), everyElement(2000));
      expect(r.recordingDone, isFalse);
    });

    test('recording keeps exactly the asked length', () {
      final r = MicTestRecorder(
        live: false,
        sampleRate: 16000,
        channels: 1,
        recordMs: 100,
      );
      for (var i = 0; i < 4; i++) {
        expect(r.add(_frame(), 1), isNull);
      }
      expect(r.recordingDone, isFalse);
      for (var i = 0; i < 3; i++) {
        r.add(_frame(), 1);
      }
      expect(r.recordingDone, isTrue);
      expect(r.takeRecording(), hasLength(4800 * 2));
    });

    test('stereo capture: the sent channel, or both mixed', () {
      final left = MicTestRecorder(
        live: true,
        sampleRate: 16000,
        channels: 2,
        outputChannel: 0,
      );
      expect(left.add(_frame(channels: 2), 1)!.last, 1000);
      final mixed = MicTestRecorder(live: true, sampleRate: 16000, channels: 2);
      expect(mixed.add(_frame(channels: 2), 1)!.last, 2000);
    });
  });

  test('live listening needs headphones', () {
    const speaker = AudioOutputDevice(
      id: 1,
      kind: AudioOutputKind.speaker,
      name: '',
    );
    const earpiece = AudioOutputDevice(
      id: 2,
      kind: AudioOutputKind.earpiece,
      name: '',
    );
    const buds = AudioOutputDevice(
      id: 3,
      kind: AudioOutputKind.bluetooth,
      name: 'Buds',
    );
    expect(headphonesConnected([speaker, earpiece]), isFalse);
    expect(headphonesConnected([speaker, buds]), isTrue);
  });

  for (final (name, voice) in [
    ('transmitting', const VoiceState(txEnabled: true)),
    ('with voice activation on', const VoiceState(voxEnabled: true)),
  ]) {
    test('the test is refused while $name', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          voiceProvider.overrideWith(() => _Voice(voice)),
          micTestWorkerFactoryProvider.overrideWithValue(
            (_) => throw StateError('must not start'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(micTestProvider, (_, _) {});
      addTearDown(sub.close);

      final refusal = await c.read(micTestProvider.notifier).start(live: false);

      expect(refusal, MicTestRefusal.transmitting);
      expect(c.read(micTestProvider), isNull);
    });
  }
}
