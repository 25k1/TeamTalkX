import 'tt_types.dart';

abstract final class TtStatusMode {
  static const available = 0x00000000;
  static const away = 0x00000001;
  static const question = 0x00000002;
  static const modeMask = 0x000000FF;

  static const male = 0x00000000;
  static const female = 0x00000100;
  static const neutral = 0x00001000;
  static const genderMask = male | female | neutral;
}

class TtUser {
  const TtUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.statusMessage,
    required this.channelId,
    required this.userState,
    required this.userType,
    required this.clientName,
    this.statusMode = 0,
    this.localSubscriptions = 0,
  });

  final int id;
  final String username;
  final String nickname;
  final String statusMessage;

  final int channelId;

  final int userState;

  final int userType;
  final String clientName;

  final int statusMode;

  final int localSubscriptions;

  TtUser copyWith({
    String? username,
    String? nickname,
    String? statusMessage,
    int? channelId,
    int? userState,
    int? userType,
    String? clientName,
    int? statusMode,
    int? localSubscriptions,
  }) => TtUser(
    id: id,
    username: username ?? this.username,
    nickname: nickname ?? this.nickname,
    statusMessage: statusMessage ?? this.statusMessage,
    channelId: channelId ?? this.channelId,
    userState: userState ?? this.userState,
    userType: userType ?? this.userType,
    clientName: clientName ?? this.clientName,
    statusMode: statusMode ?? this.statusMode,
    localSubscriptions: localSubscriptions ?? this.localSubscriptions,
  );

  bool get isTalking => (userState & UserStates.voice) != 0;

  bool get isMutedLocally => (userState & UserStates.muteVoice) != 0;

  bool get isAway => (statusMode & TtStatusMode.away) != 0;

  bool get isQuestion => (statusMode & TtStatusMode.question) != 0;

  bool get isStreamingMediaFile => (userState & UserStates.mediaFile) != 0;

  bool get isAdmin => (userType & 2) != 0;

  String get _genderEmoji => (statusMode & TtStatusMode.neutral) != 0
      ? '🧑'
      : (statusMode & TtStatusMode.female) != 0
      ? '👩'
      : '👨';

  String get _heroEmoji => (statusMode & TtStatusMode.neutral) != 0
      ? '🦸'
      : (statusMode & TtStatusMode.female) != 0
      ? '🦸‍♀️'
      : '🦸‍♂️';

  String get statusBadges {
    final activity = [
      if (isTalking) '🎤',
      if (isStreamingMediaFile) '💿',
    ].join(', ');
    final activityAndMessage = statusMessage.isNotEmpty
        ? (activity.isEmpty ? statusMessage : '$activity - $statusMessage')
        : activity;
    return [
      if (isAway) '😴' else if (isQuestion) '❓',
      if (activityAndMessage.isNotEmpty) activityAndMessage,
      isAdmin ? '$_genderEmoji ($_heroEmoji)' : _genderEmoji,
    ].join(', ');
  }

  String get displayName => nickname.isNotEmpty ? nickname : 'NoName #$id';
}

class TtChannel {
  const TtChannel({
    required this.id,
    required this.parentId,
    required this.name,
    required this.topic,
    required this.hasPassword,
    required this.maxUsers,
    required this.channelType,
    this.operators = const {},
    this.voiceUsers = const {},
    this.mediaFileUsers = const {},
  });

  final int id;

  final int parentId;
  final String name;
  final String topic;
  final bool hasPassword;
  final int maxUsers;

  final int channelType;

  final Set<int> operators;

  final Set<int> voiceUsers;

  final Set<int> mediaFileUsers;

  static const freeForAll = 0xFFF;

  bool get isRoot => parentId == 0;
  bool get isClassroom => channelType & 0x0004 != 0;

  bool mayTransmit(int userId, Set<int> users) => isClassroom
      ? users.contains(userId) || users.contains(freeForAll)
      : !users.contains(userId);
}

class TtAudioCodec {
  const TtAudioCodec({
    this.codec = AudioCodecType.opus,
    this.opusSampleRate = 48000,
    this.opusChannels = 1,
    this.opusApplication = opusApplicationVoip,
    this.opusComplexity = 10,
    this.opusFec = true,
    this.opusDtx = true,
    this.opusBitrate = 32000,
    this.opusVbr = true,
    this.opusVbrConstraint = false,
    this.opusTxIntervalMSec = 40,
    this.opusFrameSizeMSec = 40,
    this.speexBandmode = 1,
    this.speexQuality = 4,
    this.speexTxIntervalMSec = 40,
    this.speexVbrBandmode = 1,
    this.speexVbrQuality = 4,
    this.speexVbrMaxBitRate = 0,
    this.speexVbrDtx = true,
    this.speexVbrTxIntervalMSec = 40,
  });

  static const opusApplicationVoip = 2048;
  static const opusApplicationAudio = 2049;

  final AudioCodecType codec;

  final int opusSampleRate;
  final int opusChannels;
  final int opusApplication;
  final int opusComplexity;
  final bool opusFec;
  final bool opusDtx;
  final int opusBitrate;
  final bool opusVbr;
  final bool opusVbrConstraint;
  final int opusTxIntervalMSec;
  final int opusFrameSizeMSec;

  final int speexBandmode;
  final int speexQuality;
  final int speexTxIntervalMSec;

  final int speexVbrBandmode;
  final int speexVbrQuality;
  final int speexVbrMaxBitRate;
  final bool speexVbrDtx;
  final int speexVbrTxIntervalMSec;

  TtAudioCodec copyWith({
    AudioCodecType? codec,
    int? opusSampleRate,
    int? opusChannels,
    int? opusApplication,
    int? opusComplexity,
    bool? opusFec,
    bool? opusDtx,
    int? opusBitrate,
    bool? opusVbr,
    bool? opusVbrConstraint,
    int? opusTxIntervalMSec,
    int? opusFrameSizeMSec,
    int? speexBandmode,
    int? speexQuality,
    int? speexTxIntervalMSec,
    int? speexVbrBandmode,
    int? speexVbrQuality,
    int? speexVbrMaxBitRate,
    bool? speexVbrDtx,
    int? speexVbrTxIntervalMSec,
  }) => TtAudioCodec(
    codec: codec ?? this.codec,
    opusSampleRate: opusSampleRate ?? this.opusSampleRate,
    opusChannels: opusChannels ?? this.opusChannels,
    opusApplication: opusApplication ?? this.opusApplication,
    opusComplexity: opusComplexity ?? this.opusComplexity,
    opusFec: opusFec ?? this.opusFec,
    opusDtx: opusDtx ?? this.opusDtx,
    opusBitrate: opusBitrate ?? this.opusBitrate,
    opusVbr: opusVbr ?? this.opusVbr,
    opusVbrConstraint: opusVbrConstraint ?? this.opusVbrConstraint,
    opusTxIntervalMSec: opusTxIntervalMSec ?? this.opusTxIntervalMSec,
    opusFrameSizeMSec: opusFrameSizeMSec ?? this.opusFrameSizeMSec,
    speexBandmode: speexBandmode ?? this.speexBandmode,
    speexQuality: speexQuality ?? this.speexQuality,
    speexTxIntervalMSec: speexTxIntervalMSec ?? this.speexTxIntervalMSec,
    speexVbrBandmode: speexVbrBandmode ?? this.speexVbrBandmode,
    speexVbrQuality: speexVbrQuality ?? this.speexVbrQuality,
    speexVbrMaxBitRate: speexVbrMaxBitRate ?? this.speexVbrMaxBitRate,
    speexVbrDtx: speexVbrDtx ?? this.speexVbrDtx,
    speexVbrTxIntervalMSec:
        speexVbrTxIntervalMSec ?? this.speexVbrTxIntervalMSec,
  );
}

class TtChannelConfig {
  const TtChannelConfig({
    required this.name,
    this.topic = '',
    this.password = '',
    this.opPassword = '',
    required this.maxUsers,
    this.diskQuotaKB = 0,
    this.permanent = false,
    this.hidden = false,
    this.noVoiceActivation = false,
    this.noRecording = false,
    this.classroom = false,
    this.operatorRecvOnly = false,
    this.soloTransmit = false,
    this.agcEnabled = true,
    this.gainLevel = 8000,
    this.codec = const TtAudioCodec(),
  });

  final String name;
  final String topic;
  final String password;
  final String opPassword;
  final int maxUsers;
  final int diskQuotaKB;
  final bool permanent;
  final bool hidden;
  final bool noVoiceActivation;
  final bool noRecording;
  final bool classroom;
  final bool operatorRecvOnly;
  final bool soloTransmit;
  final bool agcEnabled;
  final int gainLevel;
  final TtAudioCodec codec;

  int get channelTypeMask =>
      (permanent ? ChannelTypes.permanent : 0) |
      (hidden ? ChannelTypes.hidden : 0) |
      (noVoiceActivation ? ChannelTypes.noVoiceActivation : 0) |
      (noRecording ? ChannelTypes.noRecording : 0) |
      (classroom ? ChannelTypes.classroom : 0) |
      (operatorRecvOnly ? ChannelTypes.operatorRecvOnly : 0) |
      (soloTransmit ? ChannelTypes.soloTransmit : 0);

  TtChannelConfig copyWith({
    String? name,
    String? topic,
    String? password,
    String? opPassword,
    int? maxUsers,
    int? diskQuotaKB,
    bool? permanent,
    bool? hidden,
    bool? noVoiceActivation,
    bool? noRecording,
    bool? classroom,
    bool? operatorRecvOnly,
    bool? soloTransmit,
    bool? agcEnabled,
    int? gainLevel,
    TtAudioCodec? codec,
  }) => TtChannelConfig(
    name: name ?? this.name,
    topic: topic ?? this.topic,
    password: password ?? this.password,
    opPassword: opPassword ?? this.opPassword,
    maxUsers: maxUsers ?? this.maxUsers,
    diskQuotaKB: diskQuotaKB ?? this.diskQuotaKB,
    permanent: permanent ?? this.permanent,
    hidden: hidden ?? this.hidden,
    noVoiceActivation: noVoiceActivation ?? this.noVoiceActivation,
    noRecording: noRecording ?? this.noRecording,
    classroom: classroom ?? this.classroom,
    operatorRecvOnly: operatorRecvOnly ?? this.operatorRecvOnly,
    soloTransmit: soloTransmit ?? this.soloTransmit,
    agcEnabled: agcEnabled ?? this.agcEnabled,
    gainLevel: gainLevel ?? this.gainLevel,
    codec: codec ?? this.codec,
  );
}

enum TtMsgType {
  user,
  channel,
  broadcast,
  custom;

  static TtMsgType fromValue(int value) => switch (value) {
    1 => TtMsgType.user,
    2 => TtMsgType.channel,
    3 => TtMsgType.broadcast,
    _ => TtMsgType.custom,
  };
}

class TtTextMessage {
  const TtTextMessage({
    required this.type,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.channelId,
    required this.text,
    required this.more,
  });

  final TtMsgType type;
  final int fromUserId;
  final String fromUsername;
  final int toUserId;
  final int channelId;
  final String text;

  final bool more;
}

class TtServerInfo {
  const TtServerInfo({required this.name, required this.motd});

  final String name;
  final String motd;
}

class TtServerProperties {
  const TtServerProperties({
    required this.serverName,
    required this.motd,
    required this.motdRaw,
    required this.maxUsers,
    required this.maxLoginAttempts,
    required this.maxLoginsPerIpAddress,
    required this.loginDelayMSec,
    required this.maxVoiceTxPerSecond,
    required this.maxVideoTxPerSecond,
    required this.maxMediaFileTxPerSecond,
    required this.maxDesktopTxPerSecond,
    required this.maxTotalTxPerSecond,
    required this.autoSave,
    required this.tcpPort,
    required this.udpPort,
    required this.userTimeout,
    required this.serverVersion,
    required this.protocolVersion,
    required this.serverLogEvents,
  });

  const TtServerProperties.empty()
    : serverName = '',
      motd = '',
      motdRaw = '',
      maxUsers = 128,
      maxLoginAttempts = 0,
      maxLoginsPerIpAddress = 0,
      loginDelayMSec = 0,
      maxVoiceTxPerSecond = 0,
      maxVideoTxPerSecond = 0,
      maxMediaFileTxPerSecond = 0,
      maxDesktopTxPerSecond = 0,
      maxTotalTxPerSecond = 0,
      autoSave = false,
      tcpPort = 0,
      udpPort = 0,
      userTimeout = 0,
      serverVersion = '',
      protocolVersion = '',
      serverLogEvents = 0;

  final String serverName;
  final String motd;
  final String motdRaw;
  final int maxUsers;
  final int maxLoginAttempts;
  final int maxLoginsPerIpAddress;
  final int loginDelayMSec;
  final int maxVoiceTxPerSecond;
  final int maxVideoTxPerSecond;
  final int maxMediaFileTxPerSecond;
  final int maxDesktopTxPerSecond;
  final int maxTotalTxPerSecond;
  final bool autoSave;
  final int tcpPort;
  final int udpPort;
  final int userTimeout;
  final String serverVersion;
  final String protocolVersion;

  final int serverLogEvents;
}

class TtBannedUser {
  const TtBannedUser({
    required this.ipAddress,
    required this.channelPath,
    required this.banTime,
    required this.nickname,
    required this.username,
    required this.banTypes,
  });

  final String ipAddress;
  final String channelPath;
  final String banTime;
  final String nickname;
  final String username;

  final int banTypes;

  String get displayName => nickname.isNotEmpty
      ? nickname
      : (username.isNotEmpty ? username : ipAddress);
}

class TtRemoteFile {
  const TtRemoteFile({
    required this.channelId,
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.username,
    required this.uploadTime,
  });

  final int channelId;
  final int fileId;
  final String fileName;
  final int fileSize;

  final String username;

  final String uploadTime;
}

class TtUserAccount {
  const TtUserAccount({
    this.username = '',
    this.password = '',
    this.userType = 1,
    this.userRights = 0,
    this.note = '',
    this.initChannel = '',
    this.autoOperatorChannels = const [],
    this.audioCodecBpsLimit = 0,
    this.commandsLimit = 0,
    this.commandsIntervalMSec = 0,
    this.lastModified = '',
    this.lastLogin = '',
  });

  static const maxAutoOperatorChannels = 16;

  final String username;
  final String password;

  final int userType;

  final int userRights;
  final String note;

  final String initChannel;

  final List<int> autoOperatorChannels;

  final int audioCodecBpsLimit;

  final int commandsLimit;
  final int commandsIntervalMSec;

  final String lastModified;
  final String lastLogin;

  bool get isAdmin => (userType & 2) != 0;
  bool get isDisabled => userType == 0;

  TtUserAccount copyWith({
    String? username,
    String? password,
    int? userType,
    int? userRights,
    String? note,
    String? initChannel,
    List<int>? autoOperatorChannels,
    int? audioCodecBpsLimit,
    int? commandsLimit,
    int? commandsIntervalMSec,
  }) => TtUserAccount(
    username: username ?? this.username,
    password: password ?? this.password,
    userType: userType ?? this.userType,
    userRights: userRights ?? this.userRights,
    note: note ?? this.note,
    initChannel: initChannel ?? this.initChannel,
    autoOperatorChannels: autoOperatorChannels ?? this.autoOperatorChannels,
    audioCodecBpsLimit: audioCodecBpsLimit ?? this.audioCodecBpsLimit,
    commandsLimit: commandsLimit ?? this.commandsLimit,
    commandsIntervalMSec: commandsIntervalMSec ?? this.commandsIntervalMSec,
  );
}

enum TtFileTransferStatus {
  closed,
  error,
  active,
  finished;

  static TtFileTransferStatus fromValue(int value) => switch (value) {
    1 => TtFileTransferStatus.error,
    2 => TtFileTransferStatus.active,
    3 => TtFileTransferStatus.finished,
    _ => TtFileTransferStatus.closed,
  };
}

class TtFileTransfer {
  const TtFileTransfer({
    required this.status,
    required this.transferId,
    required this.channelId,
    required this.localFilePath,
    required this.remoteFileName,
    required this.fileSize,
    required this.transferred,
    required this.inbound,
  });

  final TtFileTransferStatus status;
  final int transferId;
  final int channelId;
  final String localFilePath;
  final String remoteFileName;
  final int fileSize;
  final int transferred;

  final bool inbound;

  double get progress => fileSize <= 0 ? 0 : transferred / fileSize;
}

class TtServerStats {
  const TtServerStats({
    required this.totalTx,
    required this.totalRx,
    required this.voiceTx,
    required this.voiceRx,
    required this.mediaFileTx,
    required this.mediaFileRx,
    required this.filesTx,
    required this.filesRx,
    required this.usersServed,
    required this.usersSpoke,
    required this.uptime,
  });

  final int totalTx;
  final int totalRx;
  final int voiceTx;
  final int voiceRx;
  final int mediaFileTx;
  final int mediaFileRx;
  final int filesTx;
  final int filesRx;

  final int usersServed;

  final int usersSpoke;
  final Duration uptime;
}
