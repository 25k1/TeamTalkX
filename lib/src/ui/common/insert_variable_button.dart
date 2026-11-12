import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import 'ui.dart';

class InsertVariableButton extends StatelessWidget {
  const InsertVariableButton({
    super.key,
    required this.controller,
    required this.variables,
    this.onChanged,
  });

  final TextEditingController controller;

  final Map<String, String> variables;

  final ValueChanged<String>? onChanged;

  Future<void> _pick(BuildContext context) async {
    final token = await showAccessibleMenu<String>(
      context,
      title: context.l10n.commonInsertVariable,
      items: [
        for (final entry in variables.entries)
          MenuItemSpec(
            entry.key,
            entry.value.isEmpty ? entry.key : '${entry.key} ${entry.value}',
          ),
      ],
    );
    if (token == null) return;
    insertAtCursor(controller, token);
    onChanged?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.data_object),
    label: Text(context.l10n.commonInsertVariable),
    onPressed: () => _pick(context),
  );
}
