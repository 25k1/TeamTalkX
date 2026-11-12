import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'accessible_menu.dart';

class RowAction {
  const RowAction(this.label, this.onInvoke, {this.icon});

  final String label;
  final VoidCallback onInvoke;
  final IconData? icon;
}

class ContextMenuRow extends StatelessWidget {
  const ContextMenuRow({
    super.key,
    required this.semanticsLabel,
    required this.actions,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.selected,
    this.menuTitle,
  });

  final String semanticsLabel;
  final List<RowAction> actions;
  final Widget child;
  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  final bool? selected;

  final String? menuTitle;

  Future<void> _openMenu(BuildContext context) async {
    final action = await showAccessibleMenu<VoidCallback>(
      context,
      title: menuTitle ?? semanticsLabel,
      items: [
        for (final action in actions)
          MenuItemSpec(action.onInvoke, action.label, icon: action.icon),
      ],
    );
    action?.call();
  }

  void _onLongPress(BuildContext context) {
    if (actions.length == 1) {
      actions.first.onInvoke();
    } else if (actions.isNotEmpty) {
      unawaited(_openMenu(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final longPress =
        onLongPress ?? (actions.isEmpty ? null : () => _onLongPress(context));
    return Semantics(
      label: semanticsLabel,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: longPress,
      customSemanticsActions: {
        for (final action in actions)
          CustomSemanticsAction(label: action.label): action.onInvoke,
      },
      child: InkWell(
        onTap: onTap,
        onLongPress: longPress,
        child: actions.isEmpty
            ? child
            : Row(
                children: [
                  Expanded(child: child),
                  ExcludeSemantics(
                    child: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => unawaited(_openMenu(context)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
