import 'models.dart';

sealed class TtEvent {
  const TtEvent();
}

final class ConSuccessEvent extends TtEvent {
  const ConSuccessEvent();
}

final class ConLostEvent extends TtEvent {
  const ConLostEvent();
}

final class MyselfLoggedInEvent extends TtEvent {
  const MyselfLoggedInEvent(
    this.userId, {
    this.userRights = 0,
    this.initChannel = '',
  });
  final int userId;

  final int userRights;
  final String initChannel;
}

final class MyselfLoggedOutEvent extends TtEvent {
  const MyselfLoggedOutEvent();
}

final class MyselfKickedEvent extends TtEvent {
  const MyselfKickedEvent(this.kicker, {this.channelId});

  final int? channelId;

  bool get fromServer => channelId == null;

  final TtUser? kicker;
}

final class UserLoggedInEvent extends TtEvent {
  const UserLoggedInEvent(this.user);
  final TtUser user;
}

final class UserLoggedOutEvent extends TtEvent {
  const UserLoggedOutEvent(this.user);
  final TtUser user;
}

final class UserUpdateEvent extends TtEvent {
  const UserUpdateEvent(this.user);
  final TtUser user;
}

final class UserJoinedEvent extends TtEvent {
  const UserJoinedEvent(this.user);
  final TtUser user;
}

final class UserLeftEvent extends TtEvent {
  const UserLeftEvent(this.channelId, this.user);

  final int channelId;
  final TtUser user;
}

final class UserStateChangeEvent extends TtEvent {
  const UserStateChangeEvent(this.user);
  final TtUser user;
}

final class UserTextMessageEvent extends TtEvent {
  const UserTextMessageEvent(this.message);
  final TtTextMessage message;
}

final class ChannelNewEvent extends TtEvent {
  const ChannelNewEvent(this.channel);
  final TtChannel channel;
}

final class ChannelUpdateEvent extends TtEvent {
  const ChannelUpdateEvent(this.channel);
  final TtChannel channel;
}

final class ChannelRemoveEvent extends TtEvent {
  const ChannelRemoveEvent(this.channel);
  final TtChannel channel;
}

final class ServerUpdateEvent extends TtEvent {
  const ServerUpdateEvent(this.info);
  final TtServerInfo info;
}

final class BannedUserEvent extends TtEvent {
  const BannedUserEvent(this.ban);
  final TtBannedUser ban;
}

final class UserAccountEvent extends TtEvent {
  const UserAccountEvent(this.account);
  final TtUserAccount account;
}

final class FileNewEvent extends TtEvent {
  const FileNewEvent(this.file);
  final TtRemoteFile file;
}

final class FileRemoveEvent extends TtEvent {
  const FileRemoveEvent(this.file);
  final TtRemoteFile file;
}

final class FileTransferEvent extends TtEvent {
  const FileTransferEvent(this.transfer);
  final TtFileTransfer transfer;
}

final class MediaStreamEndedEvent extends TtEvent {
  const MediaStreamEndedEvent(this.fileName, {this.failed = false});
  final String fileName;
  final bool failed;
}

enum VoiceProblem {
  serverUnreachable,

  playbackFailed,

  microphoneFailed,

  startFailed,
}

final class VoiceProblemEvent extends TtEvent {
  const VoiceProblemEvent(this.problem, {this.detail});
  final VoiceProblem problem;

  final String? detail;
}

final class VoiceActivationEvent extends TtEvent {
  const VoiceActivationEvent({required this.active});
  final bool active;
}
