import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/files/sort.dart';
import '../../l10n/l10n.dart';

class MenuItemSpec<T> {
  const MenuItemSpec(
    this.value,
    this.label, {
    this.icon,
    this.selected = false,
  });

  final T value;
  final String label;
  final IconData? icon;

  final bool selected;
}

Future<T?> showAccessibleMenu<T>(
  BuildContext context, {
  required String title,
  required List<MenuItemSpec<T>> items,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: title,
              explicitChildNodes: true,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        Flexible(child: _MenuItems<T>(items: items)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      );
    },
  );
}

class _MenuItems<T> extends StatefulWidget {
  const _MenuItems({required this.items});

  final List<MenuItemSpec<T>> items;

  @override
  State<_MenuItems<T>> createState() => _MenuItemsState<T>();
}

class _MenuItemsState<T> extends State<_MenuItems<T>> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selected = _selectedKey.currentContext;
      if (selected != null && selected.mounted) {
        unawaited(Scrollable.ensureVisible(selected, alignment: 0.5));
      }
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in widget.items)
          Semantics(
            key: item.selected ? _selectedKey : null,
            label: item.label,
            excludeSemantics: true,
            onTap: () => Navigator.of(context).pop(item.value),
            child: ListTile(
              leading: item.icon == null ? null : Icon(item.icon),
              title: Text(item.label),
              onTap: () => Navigator.of(context).pop(item.value),
            ),
          ),
      ],
    ),
  );
}

Future<T?> showSingleChoiceMenu<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  T? selected,
}) {
  return showAccessibleMenu<T>(
    context,
    title: title,
    items: [
      for (final entry in options.entries)
        MenuItemSpec(
          entry.key,
          entry.key == selected
              ? context.l10n.commonOptionSelected(entry.value)
              : entry.value,
          icon: entry.key == selected ? Icons.check : null,
          selected: entry.key == selected,
        ),
    ],
  );
}

Future<void> showSortMenu<F extends Enum>(
  BuildContext context, {
  required String title,
  required List<F> fields,
  required String Function(F) labelOf,
  required F current,
  required bool ascending,
  required ValueChanged<F> onSelectField,
  required VoidCallback onReverse,
  required ValueChanged<String> announce,
}) async {
  const reverse = 'reverse';
  final l10n = context.l10n;
  final value = await showAccessibleMenu<String>(
    context,
    title: title,
    items: [
      for (final f in fields)
        MenuItemSpec(
          'field_${f.name}',
          f == current ? l10n.commonOptionSelected(labelOf(f)) : labelOf(f),
          icon: f == current ? Icons.check : null,
        ),
      MenuItemSpec(
        reverse,
        l10n.sortReverseOrder(
          ascending ? l10n.sortAscending : l10n.sortDescending,
        ),
        icon: Icons.swap_vert,
      ),
    ],
  );
  if (value == null) return;
  if (value == reverse) {
    onReverse();
    announce(!ascending ? l10n.sortSortedAscending : l10n.sortSortedDescending);
    return;
  }
  final field = fields.firstWhere((f) => 'field_${f.name}' == value);
  onSelectField(field);
  announce(l10n.sortSortedBy(labelOf(field)));
}

Future<void> showSortFor<F extends Enum>(
  BuildContext context, {
  required String title,
  required List<F> fields,
  required String Function(F) labelOf,
  required SortState<F> current,
  required SortNotifier<F> notifier,
  required ValueChanged<String> announce,
}) => showSortMenu<F>(
  context,
  title: title,
  fields: fields,
  labelOf: labelOf,
  current: current.field,
  ascending: current.ascending,
  onSelectField: notifier.setField,
  onReverse: notifier.toggleDirection,
  announce: announce,
);
