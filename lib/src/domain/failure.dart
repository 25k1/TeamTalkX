library;

import 'certificate.dart';

sealed class TtFailure implements Exception {
  const TtFailure();
}

final class ServerUnreachable extends TtFailure {
  const ServerUnreachable();
}

final class ConnectionTimedOut extends TtFailure {
  const ConnectionTimedOut();
}

final class SecureConnectionFailed extends TtFailure {
  const SecureConnectionFailed();
}

final class UntrustedCertificate extends TtFailure {
  const UntrustedCertificate({
    required this.host,
    required this.port,
    required this.certificate,
    required this.reason,
  });

  final String host;
  final int port;
  final CertificateInfo certificate;
  final UntrustedCertificateReason reason;
}

final class NotConnected extends TtFailure {
  const NotConnected();
}

final class ServerClosedConnection extends TtFailure {
  const ServerClosedConnection();
}

final class ServerRejected extends TtFailure {
  const ServerRejected(this.error, {this.serverMessage = ''});

  final ServerError error;

  final String serverMessage;
}

final class StorageFailure extends TtFailure {
  const StorageFailure();
}

final class MediaFileUnplayable extends TtFailure {
  const MediaFileUnplayable();
}

final class RecordingFailed extends TtFailure {
  const RecordingFailed();
}

final class WebServiceFailure extends TtFailure {
  const WebServiceFailure();
}

final class WebLoginRequired extends TtFailure {
  const WebLoginRequired();
}

final class UnexpectedFailure extends TtFailure {
  const UnexpectedFailure(this.detail);

  final String detail;
}

enum ServerError {
  syntaxError(1000),
  unknownCommand(1001),
  missingParameter(1002),
  incompatibleProtocols(1003),
  unknownAudioCodec(1004),
  invalidUsername(1005),
  incorrectChannelPassword(2001),
  invalidAccount(2002),
  serverFull(2003),
  channelFull(2004),
  bannedFromServer(2005),
  notAuthorized(2006),
  diskQuotaExceeded(2008),
  incorrectOpPassword(2010),
  bitrateLimitExceeded(2011),
  tooManyLoginsFromAddress(2012),
  tooManyChannels(2013),
  commandFlood(2014),
  bannedFromChannel(2015),
  tooManyTransfers(2016),
  notLoggedIn(3000),
  alreadyLoggedIn(3001),
  notInChannel(3002),
  alreadyInChannel(3003),
  channelExists(3004),
  channelNotFound(3005),
  userNotFound(3006),
  banNotFound(3007),
  transferNotFound(3008),
  openFileFailed(3009),
  accountNotFound(3010),
  fileNotFound(3011),
  fileExists(3012),
  fileSharingDisabled(3013),
  channelHasUsers(3015),
  loginServiceUnavailable(3016),
  channelCannotBeHidden(3017),
  other(-1);

  const ServerError(this.code);

  final int code;

  static ServerError fromCode(int code) =>
      values.firstWhere((e) => e.code == code, orElse: () => ServerError.other);
}
