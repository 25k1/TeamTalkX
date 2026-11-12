import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'text_controllers.dart';

enum _Leave { save, discard, stay }

mixin UnsavedChanges<T extends StatefulWidget> on TextControllers<T> {
  String? _saved;

  List<Object?> get formValues;

  String get _signature =>
      [for (final c in textControllers) c.text, ...formValues].join('\u0001');

  void markSaved() => _saved = _signature;

  bool get hasUnsavedChanges => _saved != null && _saved != _signature;

  Widget guardUnsaved({
    required Widget child,
    required FutureOr<void> Function() save,
  }) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final navigator = Navigator.of(context);
      if (!hasUnsavedChanges) {
        navigator.pop();
        return;
      }
      final l10n = context.l10n;
      final choice = await showDialog<_Leave>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.serverEditUnsavedTitle),
          content: Text(l10n.serverEditUnsavedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_Leave.stay),
              child: Text(l10n.serverEditKeepEditing),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_Leave.discard),
              child: Text(l10n.commonDiscard),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_Leave.save),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      );
      if (!mounted) return;
      switch (choice ?? _Leave.stay) {
        case _Leave.save:
          await save();
        case _Leave.discard:
          navigator.pop();
        case _Leave.stay:
          break;
      }
    },
    child: child,
  );
}
