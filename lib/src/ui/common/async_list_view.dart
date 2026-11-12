import 'package:flutter/material.dart';
import '../../domain/failure.dart';
import '../../l10n/failure_messages.dart';
import '../../l10n/l10n.dart';

class AsyncListView<T> extends StatelessWidget {
  const AsyncListView({
    super.key,
    required this.loading,
    required this.failure,
    required this.items,
    required this.loadingLabel,
    required this.errorPrefix,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  final bool loading;

  final TtFailure? failure;
  final List<T> items;
  final String loadingLabel;

  final String errorPrefix;
  final String emptyMessage;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: Semantics(
          label: loadingLabel,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (failure case final failure?) {
      return Center(
        child: Text(
          context.l10n.failureReport(
            errorPrefix,
            context.l10n.failureMessage(failure),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => itemBuilder(context, items[index]),
    );
  }
}
