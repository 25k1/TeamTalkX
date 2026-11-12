import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

class ListSearchField extends StatefulWidget {
  const ListSearchField({
    super.key,
    required this.label,
    required this.onChanged,
  });

  final String label;
  final ValueChanged<String> onChanged;

  @override
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: context.l10n.commonClearSearch,
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value.trim());
      },
    ),
  );
}

bool matchesSearch(String query, Iterable<String> fields) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  return fields.any((f) => f.toLowerCase().contains(q));
}
