import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/events.dart';
import '../../domain/failure.dart';
import '../failures.dart';
import 'client_events.dart';
import 'connection_providers.dart';

mixin ServerListLoader<T, W extends ConsumerStatefulWidget>
    on ConsumerState<W> {
  final List<T> items = [];
  bool loading = true;

  TtFailure? failure;

  Future<void> loadList({
    required Future<void> Function() command,
    required T? Function(TtEvent event) match,
  }) async {
    final client = ref.read(teamTalkClientProvider);
    setState(() {
      items.clear();
      loading = true;
      failure = null;
    });
    await collectListCommand<T>(
      client,
      command: command,
      match: match,
      onItem: (item) {
        if (mounted) setState(() => items.add(item));
      },
      onError: (e) {
        if (mounted) setState(() => failure = failureFrom(e));
      },
    );
    if (mounted) setState(() => loading = false);
  }
}
