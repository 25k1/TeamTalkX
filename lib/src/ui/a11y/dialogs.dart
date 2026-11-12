import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../common/password_field.dart';

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? context.l10n.commonOk),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? label,
  String initialValue = '',
  bool obscureText = false,
  String? submitLabel,
  String? cancelLabel,
  bool barrierDismissible = true,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => _PromptDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      obscureText: obscureText,
      submitLabel: submitLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.obscureText,
    this.submitLabel,
    this.cancelLabel,
  });

  final String title;
  final String? label;
  final String initialValue;
  final bool obscureText;
  final String? submitLabel;
  final String? cancelLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: widget.obscureText
          ? PasswordField(
              controller: _controller,
              label: widget.label ?? '',
              autofocus: true,
              onSubmitted: (_) => _submit(),
            )
          : TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(labelText: widget.label),
              onSubmitted: (_) => _submit(),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel ?? context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.submitLabel ?? context.l10n.commonOk),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
