import 'dart:async';

import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';

class FakeVoiceClient implements TeamTalkClient {
  final eventController = StreamController<TtEvent>.broadcast();
  final voiceController = StreamController<bool>.broadcast(sync: true);
  final statuses = <(int, String)>[];
  final transmits = <bool>[];
  int captureStarts = 0;
  int captureStops = 0;

  @override
  final ServerState state = ServerState();
  @override
  Stream<TtEvent> get events => eventController.stream;
  @override
  bool get isVoiceTransmitting => false;
  @override
  int beginAudioInput() => 1;
  @override
  void endAudioInput() {}
  @override
  void configureCapture(CaptureSettings s) {}
  @override
  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) => captureStarts++;
  @override
  void stopCapture() => captureStops++;
  @override
  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) => transmits.add(transmit);
  @override
  Stream<bool> get captureVoice => voiceController.stream;
  @override
  void resetCapture() {}
  @override
  bool setVoiceActivation({required bool enabled}) => true;
  @override
  bool setVoiceActivationLevel(int level) => true;
  @override
  bool setVoiceTransmission({required bool enabled}) => true;
  @override
  void applyLocalEvent(TtEvent event) => eventController.add(event);
  @override
  Future<void> changeStatus(int statusMode, String statusMessage) async {
    statuses.add((statusMode, statusMessage));
    final me = state.users[state.myUserId]!;
    state.apply(
      UserUpdateEvent(
        me.copyWith(statusMode: statusMode, statusMessage: statusMessage),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void addMe({int statusMode = 0, String statusMessage = 'hello'}) {
    state
      ..apply(const MyselfLoggedInEvent(7))
      ..apply(
        UserLoggedInEvent(
          TtUser(
            id: 7,
            username: '',
            nickname: 'me',
            statusMessage: statusMessage,
            channelId: 1,
            userState: 0,
            userType: 1,
            clientName: '',
            statusMode: statusMode,
          ),
        ),
      );
  }

  Future<void> close() async {
    await eventController.close();
    await voiceController.close();
  }
}
