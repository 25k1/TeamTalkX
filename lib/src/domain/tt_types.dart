library;

const String teamTalkSdkVersion = '5.23.0.5201';

enum AudioCodecType {
  none(0),
  speex(1),
  speexVbr(2),
  opus(3);

  const AudioCodecType(this.value);

  final int value;

  static AudioCodecType fromValue(int value) => values.firstWhere(
    (c) => c.value == value,
    orElse: () => AudioCodecType.none,
  );
}

abstract final class ChannelTypes {
  static const int permanent = 0x0001;
  static const int soloTransmit = 0x0002;
  static const int classroom = 0x0004;
  static const int operatorRecvOnly = 0x0008;
  static const int noVoiceActivation = 0x0010;
  static const int noRecording = 0x0020;
  static const int hidden = 0x0040;
}

abstract final class UserRights {
  static const int none = 0x00000000;
  static const int multiLogin = 0x00000001;
  static const int viewAllUsers = 0x00000002;
  static const int createTemporaryChannel = 0x00000004;
  static const int modifyChannels = 0x00000008;
  static const int textMessageBroadcast = 0x00000010;
  static const int kickUsers = 0x00000020;
  static const int banUsers = 0x00000040;
  static const int moveUsers = 0x00000080;
  static const int operatorEnable = 0x00000100;
  static const int uploadFiles = 0x00000200;
  static const int downloadFiles = 0x00000400;
  static const int updateServerProperties = 0x00000800;
  static const int transmitVoice = 0x00001000;
  static const int transmitVideoCapture = 0x00002000;
  static const int transmitDesktop = 0x00004000;
  static const int transmitDesktopInput = 0x00008000;
  static const int transmitMediaFileAudio = 0x00010000;
  static const int transmitMediaFileVideo = 0x00020000;
  static const int transmitMediaFile =
      transmitMediaFileAudio | transmitMediaFileVideo;
  static const int lockedNickname = 0x00040000;
  static const int lockedStatus = 0x00080000;
  static const int recordVoice = 0x00100000;
  static const int viewHiddenChannels = 0x00200000;
  static const int textMessageUser = 0x00400000;
  static const int textMessageChannel = 0x00800000;
}

abstract final class UserTypes {
  static const int none = 0x0;
  static const int defaultUser = 0x1;
  static const int admin = 0x2;
}

abstract final class UserStates {
  static const int none = 0x00;
  static const int voice = 0x01;
  static const int muteVoice = 0x02;
  static const int muteMediaFile = 0x04;
  static const int desktop = 0x08;
  static const int videoCapture = 0x10;
  static const int mediaFileAudio = 0x20;
  static const int mediaFileVideo = 0x40;
  static const int mediaFile = mediaFileAudio | mediaFileVideo;
}

abstract final class Subscriptions {
  static const int none = 0x00000000;
  static const int userMsg = 0x00000001;
  static const int channelMsg = 0x00000002;
  static const int broadcastMsg = 0x00000004;
  static const int customMsg = 0x00000008;
  static const int voice = 0x00000010;
  static const int videoCapture = 0x00000020;
  static const int desktop = 0x00000040;
  static const int desktopInput = 0x00000080;
  static const int mediaFile = 0x00000100;
  static const int interceptUserMsg = 0x00010000;
  static const int interceptChannelMsg = 0x00020000;
  static const int interceptCustomMsg = 0x00080000;
  static const int interceptVoice = 0x00100000;
  static const int interceptVideoCapture = 0x00200000;
  static const int interceptDesktop = 0x00400000;
  static const int interceptMediaFile = 0x01000000;
}

abstract final class BanTypes {
  static const int none = 0x00;
  static const int channel = 0x01;
  static const int ipAddress = 0x02;
  static const int username = 0x04;
}

enum ServerLogEvent {
  userConnected(0x00000001),
  userDisconnected(0x00000002),
  userLoggedIn(0x00000004),
  userLoggedOut(0x00000008),
  userLoginFailed(0x00000010),
  userTimedOut(0x00000020),
  userKicked(0x00000040),
  userBanned(0x00000080),
  userUnbanned(0x00000100),
  userUpdated(0x00000200),
  userJoinedChannel(0x00000400),
  userLeftChannel(0x00000800),
  userMoved(0x00001000),
  userTextMessagePrivate(0x00002000),
  userTextMessageCustom(0x00004000),
  userTextMessageChannel(0x00008000),
  userTextMessageBroadcast(0x00010000),
  channelCreated(0x00020000),
  channelUpdated(0x00040000),
  channelRemoved(0x00080000),
  fileUploaded(0x00100000),
  fileDownloaded(0x00200000),
  fileDeleted(0x00400000),
  serverUpdated(0x00800000),
  serverSaveConfig(0x01000000),
  userCryptError(0x02000000),
  userNewStream(0x04000000);

  const ServerLogEvent(this.value);

  final int value;
}
