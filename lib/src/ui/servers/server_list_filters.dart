import 'package:flutter/material.dart';

import '../../app/servers/public_server_filter.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';

extension PublicSortLabel on PublicSort {
  String label(AppLocalizations l10n) => switch (this) {
    PublicSort.users => l10n.serverSortUsers,
    PublicSort.name => l10n.serverSortName,
    PublicSort.country => l10n.serverSortCountry,
  };
}

class ServerSearchField extends StatelessWidget {
  const ServerSearchField({
    required this.controller,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: context.l10n.serverClearSearch,
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
      onChanged: (value) => onChanged(value.trim()),
    ),
  );
}

Future<void> pickFromMenu<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T selected,
  required void Function(T) onPick,
}) async {
  final picked = await showSingleChoiceMenu<T>(
    context,
    title: title,
    options: options,
    selected: selected,
  );
  if (picked != null) onPick(picked);
}

Future<void> showPublicFilterMenu(
  BuildContext context, {
  required PublicServerFilter filter,
  required List<String> countries,
  required void Function(PublicServerFilter) onChanged,
}) async {
  final l10n = context.l10n;
  const minUsers = [0, 1, 5, 10, 20];
  String usersLabel(int n) =>
      n == 0 ? l10n.serverFilterAny : l10n.serverFilterAtLeast(n);
  final choice = await showAccessibleMenu<String>(
    context,
    title: l10n.serverFilterAndSort,
    items: [
      MenuItemSpec(
        'country',
        '${l10n.serverFilterCountry}: '
            '${filter.country.isEmpty ? l10n.serverFilterAny : filter.country}',
        icon: Icons.public,
      ),
      MenuItemSpec(
        'users',
        '${l10n.serverFilterUsers}: ${usersLabel(filter.minUsers)}',
        icon: Icons.people,
      ),
      MenuItemSpec(
        'sort',
        '${l10n.serverSortOrder}: ${filter.sort.label(l10n)}',
        icon: Icons.sort,
      ),
      if (filter.isActive)
        MenuItemSpec(
          'clear',
          l10n.serverClearFiltersAction,
          icon: Icons.filter_alt_off,
        ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'country':
      await pickFromMenu<String>(
        context,
        title: l10n.serverFilterCountry,
        options: {'': l10n.serverFilterAny, for (final c in countries) c: c},
        selected: filter.country,
        onPick: (c) => onChanged(filter.copyWith(country: c)),
      );
    case 'users':
      await pickFromMenu<int>(
        context,
        title: l10n.serverFilterUsers,
        options: {for (final n in minUsers) n: usersLabel(n)},
        selected: filter.minUsers,
        onPick: (n) => onChanged(filter.copyWith(minUsers: n)),
      );
    case 'sort':
      await pickFromMenu<PublicSort>(
        context,
        title: l10n.serverSortOrder,
        options: {for (final s in PublicSort.values) s: s.label(l10n)},
        selected: filter.sort,
        onPick: (s) => onChanged(filter.copyWith(sort: s)),
      );
    case 'clear':
      onChanged(filter.copyWith(country: '', minUsers: 0));
  }
}
