import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/failure.dart';

const reconnectFirstDelay = Duration(seconds: 2);
const reconnectMaxDelay = Duration(seconds: 60);

Duration reconnectDelay(int failures, Random random) {
  final base = min(
    reconnectFirstDelay.inMilliseconds * pow(2, min(failures, 16)),
    reconnectMaxDelay.inMilliseconds.toDouble(),
  );
  final jittered = base * (0.8 + 0.4 * random.nextDouble());
  return Duration(
    milliseconds: jittered.round().clamp(
      reconnectFirstDelay.inMilliseconds * 4 ~/ 5,
      reconnectMaxDelay.inMilliseconds,
    ),
  );
}

bool endsReconnecting(TtFailure failure) => switch (failure) {
  WebLoginRequired() || UntrustedCertificate() => true,
  ServerRejected(:final error) => switch (error) {
    ServerError.invalidAccount ||
    ServerError.invalidUsername ||
    ServerError.bannedFromServer ||
    ServerError.notAuthorized ||
    ServerError.incompatibleProtocols => true,
    _ => false,
  },
  _ => false,
};

class ReconnectScheduler {
  ReconnectScheduler({Random? random}) : random = random ?? Random();

  final Random random;

  DateTime now() => DateTime.now();

  Timer start(Duration delay, void Function() callback) =>
      Timer(delay, callback);
}

final reconnectSchedulerProvider = Provider<ReconnectScheduler>(
  (ref) => ReconnectScheduler(),
);
