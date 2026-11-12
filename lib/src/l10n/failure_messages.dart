import '../domain/certificate.dart';
import '../domain/failure.dart';
import 'generated/app_localizations.dart';

extension FailureMessages on AppLocalizations {
  String failureMessage(TtFailure failure) => switch (failure) {
    ServerUnreachable() => failureServerUnreachable,
    ConnectionTimedOut() => failureTimedOut,
    SecureConnectionFailed() => failureSecureConnection,
    UntrustedCertificate(:final reason) => switch (reason) {
      NewCertificate() => failureCertificateNew,
      ChangedCertificate() => failureCertificateChanged,
    },
    NotConnected() => failureNotConnected,
    ServerClosedConnection() => failureServerClosed,
    StorageFailure() => failureStorage,
    MediaFileUnplayable() => failureMediaFileUnplayable,
    RecordingFailed() => failureRecording,
    WebServiceFailure() => failureWebService,
    WebLoginRequired() => failureWebLoginRequired,
    UnexpectedFailure() => failureUnexpected,
    ServerRejected(:final error, :final serverMessage) => _serverError(
      error,
      serverMessage,
    ),
  };

  String _serverError(
    ServerError error,
    String serverMessage,
  ) => switch (error) {
    ServerError.syntaxError ||
    ServerError.unknownCommand ||
    ServerError.missingParameter ||
    ServerError.incompatibleProtocols => serverErrorProtocol,
    ServerError.unknownAudioCodec => serverErrorUnknownAudioCodec,
    ServerError.invalidUsername => serverErrorInvalidUsername,
    ServerError.incorrectChannelPassword => serverErrorIncorrectChannelPassword,
    ServerError.invalidAccount => serverErrorInvalidAccount,
    ServerError.serverFull => serverErrorServerFull,
    ServerError.channelFull => serverErrorChannelFull,
    ServerError.bannedFromServer => serverErrorBannedFromServer,
    ServerError.notAuthorized => serverErrorNotAuthorized,
    ServerError.diskQuotaExceeded => serverErrorDiskQuota,
    ServerError.incorrectOpPassword => serverErrorIncorrectOpPassword,
    ServerError.bitrateLimitExceeded => serverErrorBitrateLimit,
    ServerError.tooManyLoginsFromAddress => serverErrorTooManyLogins,
    ServerError.tooManyChannels => serverErrorTooManyChannels,
    ServerError.commandFlood => serverErrorCommandFlood,
    ServerError.bannedFromChannel => serverErrorBannedFromChannel,
    ServerError.tooManyTransfers => serverErrorTooManyTransfers,
    ServerError.notLoggedIn => serverErrorNotLoggedIn,
    ServerError.alreadyLoggedIn => serverErrorAlreadyLoggedIn,
    ServerError.notInChannel => serverErrorNotInChannel,
    ServerError.alreadyInChannel => serverErrorAlreadyInChannel,
    ServerError.channelExists => serverErrorChannelExists,
    ServerError.channelNotFound => serverErrorChannelNotFound,
    ServerError.userNotFound => serverErrorUserNotFound,
    ServerError.banNotFound => serverErrorBanNotFound,
    ServerError.transferNotFound => serverErrorTransferNotFound,
    ServerError.openFileFailed => serverErrorOpenFileFailed,
    ServerError.accountNotFound => serverErrorAccountNotFound,
    ServerError.fileNotFound => serverErrorFileNotFound,
    ServerError.fileExists => serverErrorFileExists,
    ServerError.fileSharingDisabled => serverErrorFileSharingDisabled,
    ServerError.channelHasUsers => serverErrorChannelHasUsers,
    ServerError.loginServiceUnavailable => serverErrorLoginServiceUnavailable,
    ServerError.channelCannotBeHidden => serverErrorChannelCannotBeHidden,
    ServerError.other => failureServerOther(serverMessage),
  };
}
