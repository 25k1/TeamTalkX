import 'dart:async';

import 'package:flutter/material.dart';

void pushScreen(BuildContext context, Widget screen) {
  unawaited(pushScreenForResult<void>(context, screen));
}

Future<T?> pushScreenForResult<T>(BuildContext context, Widget screen) {
  return Navigator.of(
    context,
  ).push<T>(MaterialPageRoute<T>(builder: (_) => screen));
}

int intFromField(TextEditingController controller, int fallback) =>
    int.tryParse(controller.text.trim()) ?? fallback;

void insertAtCursor(TextEditingController controller, String token) {
  final text = controller.text;
  final sel = controller.selection;
  final start = sel.start >= 0 ? sel.start : text.length;
  final end = sel.end >= 0 ? sel.end : text.length;
  controller.value = TextEditingValue(
    text: text.replaceRange(start, end, token),
    selection: TextSelection.collapsed(offset: start + token.length),
  );
}

void setControllerText(TextEditingController controller, String text) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

extension SnackBarMessenger on ScaffoldMessengerState {
  void showMessage(String text) => showSnackBar(SnackBar(content: Text(text)));

  void showUndo(
    String text, {
    required String undoLabel,
    required VoidCallback onUndo,
  }) => showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    ),
  );
}
