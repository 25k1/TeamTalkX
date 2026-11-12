import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/native_pm_notifications.dart';
import '../platform_services.dart';
import 'pm_providers.dart';

final pmNotificationRepliesProvider = Provider<void>((ref) {
  final sub = ref.read(pmNotificationsProvider).replies.listen((reply) {
    final (userId, text) = reply;
    unawaited(ref.read(pmProvider.notifier).send(userId, text));
  });
  ref.onDispose(sub.cancel);
});

final pmOpenRequestsProvider = Provider<Stream<int>>(
  (ref) => _openRequests(ref.read(pmNotificationsProvider)),
);

Stream<int> _openRequests(PmNotifications notifications) async* {
  final initial = await notifications.initialPm();
  if (initial > 0) yield initial;
  yield* notifications.openRequests;
}
