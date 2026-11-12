import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../../domain/teamtalk_client.dart';
import 'connection_providers.dart';

Future<void> collectListCommand<T>(
  TeamTalkClient client, {
  required Future<void> Function() command,
  required T? Function(TtEvent event) match,
  required void Function(T item) onItem,
  required void Function(Object error) onError,
}) async {
  final sub = client.events.listen((event) {
    final item = match(event);
    if (item != null) onItem(item);
  });
  try {
    await command();
  } on Object catch (e, st) {
    appLog.w('command', 'List command failed', e, st);
    onError(e);
  } finally {
    await sub.cancel();
  }
}

extension ClientEventListening on Ref {
  StreamSubscription<TtEvent> listenClientEvents(
    void Function(TtEvent event) onEvent,
  ) {
    final sub = read(teamTalkClientProvider).events.listen(onEvent);
    onDispose(sub.cancel);
    return sub;
  }
}
