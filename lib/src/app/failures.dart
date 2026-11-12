import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/failure.dart';
import '../protocol/tt_connection.dart';

TtFailure failureFrom(Object error) => switch (error) {
  TtFailure() => error,
  TtCommandError(:final number, :final message) => ServerRejected(
    ServerError.fromCode(number),
    serverMessage: message,
  ),
  TimeoutException() => const ConnectionTimedOut(),
  TlsException() => const SecureConnectionFailed(),
  SocketException() => const ServerUnreachable(),
  HttpException() => const WebServiceFailure(),
  FileSystemException() => const StorageFailure(),
  PlatformException(:final code, :final message) => UnexpectedFailure(
    'platform $code: $message',
  ),
  _ => UnexpectedFailure(error.toString()),
};
