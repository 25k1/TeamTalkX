import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/server_entry.dart';
import '../settings/settings_providers.dart';

enum PublicSort {
  users,
  name,
  country;

  static PublicSort fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => users);
}

enum MineSort {
  yours,
  name,
  recent;

  static MineSort fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => yours);
}

class PublicServerFilter {
  const PublicServerFilter({
    this.country = '',
    this.minUsers = 0,
    this.sort = PublicSort.users,
    this.mineSort = MineSort.yours,
  });

  final PublicSort sort;
  final MineSort mineSort;

  final String country;

  final int minUsers;

  bool get isActive => country.isNotEmpty || minUsers > 0;

  bool allows(ServerEntry entry) =>
      (country.isEmpty || entry.country == country) &&
      entry.userCount >= minUsers;

  PublicServerFilter copyWith({
    String? country,
    int? minUsers,
    PublicSort? sort,
    MineSort? mineSort,
  }) => PublicServerFilter(
    country: country ?? this.country,
    minUsers: minUsers ?? this.minUsers,
    sort: sort ?? this.sort,
    mineSort: mineSort ?? this.mineSort,
  );

  List<ServerEntry> sorted(Iterable<ServerEntry> servers) {
    int byName(ServerEntry a, ServerEntry b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    return servers.toList()..sort(
      (a, b) => switch (sort) {
        PublicSort.users =>
          b.userCount != a.userCount
              ? b.userCount.compareTo(a.userCount)
              : byName(a, b),
        PublicSort.name => byName(a, b),
        PublicSort.country =>
          a.country != b.country
              ? a.country.compareTo(b.country)
              : byName(a, b),
      },
    );
  }

  List<(ServerEntry, int)> sortedMine(List<(ServerEntry, int)> servers) {
    final list = [...servers];
    switch (mineSort) {
      case MineSort.yours:
        break;
      case MineSort.name:
        list.sort(
          (a, b) => a.$1.displayName.toLowerCase().compareTo(
            b.$1.displayName.toLowerCase(),
          ),
        );
      case MineSort.recent:
        final never = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort(
          (a, b) => (b.$1.lastConnected ?? never).compareTo(
            a.$1.lastConnected ?? never,
          ),
        );
    }
    return list;
  }
}

final publicServerFilterProvider =
    NotifierProvider<PublicServerFilterNotifier, PublicServerFilter>(
      PublicServerFilterNotifier.new,
    );

class PublicServerFilterNotifier extends Notifier<PublicServerFilter> {
  static const _countryKey = 'public_filter_country';
  static const _minUsersKey = 'public_filter_min_users';
  static const _sortKey = 'public_sort';
  static const _mineSortKey = 'mine_sort';

  @override
  PublicServerFilter build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return PublicServerFilter(
      country: prefs.getString(_countryKey) ?? '',
      minUsers: prefs.getInt(_minUsersKey) ?? 0,
      sort: PublicSort.fromName(prefs.getString(_sortKey)),
      mineSort: MineSort.fromName(prefs.getString(_mineSortKey)),
    );
  }

  void set(PublicServerFilter filter) {
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(prefs.setString(_countryKey, filter.country));
    unawaited(prefs.setInt(_minUsersKey, filter.minUsers));
    unawaited(prefs.setString(_sortKey, filter.sort.name));
    unawaited(prefs.setString(_mineSortKey, filter.mineSort.name));
    state = filter;
  }
}

List<String> countriesOf(Iterable<ServerEntry> servers) => {
  for (final s in servers)
    if (s.country.isNotEmpty) s.country,
}.toList()..sort();
