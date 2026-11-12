import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../announcer.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../settings/locale_providers.dart';

final userSelectionProvider = NotifierProvider<UserSelectionNotifier, Set<int>>(
  UserSelectionNotifier.new,
);

class UserSelectionNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    ref.listenClientEvents((event) {
      switch (event) {
        case ConLostEvent() || MyselfLoggedOutEvent():
          state = const {};
        case UserLoggedOutEvent(:final user):
          if (state.contains(user.id)) {
            state = {...state}..remove(user.id);
          }
        default:
          break;
      }
    });
    return const {};
  }

  void toggle(int userId) {
    state = state.contains(userId)
        ? ({...state}..remove(userId))
        : {...state, userId};
  }

  void clear() => state = const {};

  Future<(int, int)> moveTo(int channelId) async {
    final ids = state;
    if (ids.isEmpty) return (0, 0);
    final client = ref.read(teamTalkClientProvider);
    var moved = 0;
    for (final id in ids) {
      try {
        await client.moveUser(id, channelId);
        moved++;
      } on Object catch (e, st) {
        appLog.w('users', 'Moving user $id failed', e, st);
      }
    }
    clear();
    ref
        .read(announcerProvider)
        .announce(
          ref.read(appLocalizationsProvider).selectionUsersMoved(moved),
        );
    return (moved, ids.length);
  }
}
