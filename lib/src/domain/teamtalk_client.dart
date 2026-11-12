import 'dart:async';

import 'capture_settings.dart';
import 'events.dart';
import 'media_stream.dart';
import 'models.dart';
import 'recording.dart';
import 'server_state.dart';
import 'voice_quality.dart';

abstract interface class TeamTalkClient {
  ServerState get state;

  Stream<TtEvent> get events;

  bool get isConnected;
  bool get isVoiceTransmitting;
  bool get isVoiceActivationEnabled;
  int get myUserId;
  int get rootChannelId;
  String get serverAccessToken;
  bool get isAdmin;
  int get serverMaxUsers;
  bool get isStreamingMediaFile;
  int get voiceActivationLevel;
  int get masterVolume;
  int get microphoneGain;

  int beginAudioInput();

  void configureCapture(CaptureSettings settings);

  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  });
  void stopCapture();

  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll,
    bool voiceActive,
  });

  Stream<bool> get captureVoice;

  void resetCapture();
  void endAudioInput();
  void setSoundOutputMute({required bool muted});

  Future<void> connect(
    String host, {
    int tcpPort,
    int udpPort,
    bool encrypted,
    Duration timeout,
  });
  void disconnect();
  Future<void> login({
    required String nickname,
    String username,
    String password,
    String clientName,
  });
  Future<void> logout();

  Future<void> joinChannel(int channelId, {String password});
  int channelIdFromPath(String path);
  String channelPath(int channelId);
  Future<void> leaveChannel();

  Future<void> sendChannelMessage(int channelId, String text);
  Future<void> sendUserMessage(int userId, String text);
  Future<void> sendBroadcastMessage(String text);
  Future<void> sendCustomMessage(int userId, String text);

  Future<void> changeStatus(int statusMode, String statusMessage);
  Future<void> changeNickname(String nickname);
  Future<void> subscribe(int userId, int subscriptions);
  Future<void> unsubscribe(int userId, int subscriptions);
  void refreshUser(int userId);

  Future<void> listBans({int channelId, int index, int count});
  Future<void> unbanUser(TtBannedUser ban);
  Future<void> addBan({
    String ipAddress,
    String username,
    String channelPath,
    required int banTypes,
  });

  Future<void> listUserAccounts({int index, int count});
  Future<void> createUserAccount(TtUserAccount account);
  Future<void> deleteUserAccount(String username);

  TtServerProperties getServerProperties();
  Future<void> updateServer(TtServerProperties p);

  TtChannelConfig getChannelConfig(int channelId);
  Future<void> saveChannel(
    TtChannelConfig cfg, {
    int? parentId,
    int? channelId,
  });
  Future<void> removeChannel(int channelId);

  Future<void> startStreamingMediaFile(
    String path, {
    required String fileName,
    bool loop = false,
    int volumePercent = 100,
    bool monitor = false,
  });

  MediaStreamState? get mediaStream;

  Stream<MediaStreamState?> get mediaStreamChanges;

  void setMediaStreamPaused({required bool paused});
  void seekMediaStream(Duration position);
  void seekMediaStreamBy(Duration offset);
  void setMediaStreamLoop({required bool loop});
  void setMediaStreamVolume(int percent);
  void setMediaStreamMonitor({required bool monitor});
  void stopStreamingMediaFile();

  Future<void> startRecording({
    required String directory,
    required RecordingMode mode,
    required RecordingFormat format,
  });

  bool get isRecording;

  Future<void> stopRecording();

  Future<void> sendFile(int channelId, String localPath);
  Future<void> recvFile(int channelId, int fileId, String localPath);
  Future<void> deleteFile(int channelId, int fileId);
  bool cancelFileTransfer(int transferId);
  TtFileTransfer? getFileTransferInfo(int transferId);

  Future<void> kickUser(int userId, {int channelId});

  Future<void> banUser(int userId, {int channelId, int banTypes});
  Future<void> moveUser(int userId, int channelId);

  Future<void> channelOperator(
    int userId,
    int channelId, {
    required bool makeOperator,
    String password = '',
  });

  Future<void> setTransmitUsers(
    int channelId, {
    required Set<int> voice,
    required Set<int> mediaFiles,
  });

  TtUser? getUser(int userId);
  int getUserVolume(int userId, {bool media});
  bool setUserVolume(int userId, int volume, {bool media});
  bool isUserMuted(int userId, {bool media});
  bool setUserMute(int userId, {required bool muted, bool media});
  bool isChannelOperator(int userId, int channelId);

  Future<TtServerStats> queryServerStats();

  bool setVoiceTransmission({required bool enabled});
  bool setVoiceActivation({required bool enabled});
  bool setVoiceActivationLevel(int level);

  bool setMasterVolume(int volume);

  void setMediaPlaybackVolume(int percent);

  void setPlaybackNormalization({required bool enabled});

  void setVoiceQuality(VoiceQuality quality);

  void setAudioOutput({required bool voiceCall, int deviceId = 0});
  bool setMicrophoneGain(int gain);

  void applyLocalEvent(TtEvent event);

  bool get supportsInputGain => true;

  void dispose();
}
