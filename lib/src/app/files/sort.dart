import 'package:flutter_riverpod/flutter_riverpod.dart';

class SortState<F> {
  const SortState(this.field, {this.ascending = true});

  final F field;
  final bool ascending;

  SortState<F> copyWith({F? field, bool? ascending}) =>
      SortState(field ?? this.field, ascending: ascending ?? this.ascending);
}

abstract class SortNotifier<F> extends Notifier<SortState<F>> {
  F get defaultField;

  @override
  SortState<F> build() => SortState(defaultField);

  void setField(F field) => state = state.copyWith(field: field);

  void toggleDirection() => state = state.copyWith(ascending: !state.ascending);
}
