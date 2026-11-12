import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../common/password_field.dart';

class LabeledTextField extends StatelessWidget {
  const LabeledTextField({
    super.key,
    required this.controller,
    required this.label,
    this.number = false,
    this.obscure = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool number;
  final bool obscure;
  final bool readOnly;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: obscure
          ? PasswordField(
              controller: controller,
              label: label,
              validator: validator,
            )
          : TextFormField(
              controller: controller,
              readOnly: readOnly,
              maxLines: maxLines,
              keyboardType: number ? TextInputType.number : null,
              inputFormatters: number
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              decoration: InputDecoration(labelText: label),
              validator: validator,
            ),
    );
  }
}

class LevelSlider extends StatefulWidget {
  const LevelSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    required this.max,
    this.percent = false,
    this.step = 1,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final int value;
  final int min;
  final int max;

  final bool percent;
  final int step;
  final ValueChanged<int> onChanged;

  final ValueChanged<int>? onChangeEnd;

  @override
  State<LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<LevelSlider> {
  static const _announceInterval = Duration(milliseconds: 150);

  bool _dragging = false;
  int? _lastAnnounced;
  DateTime _lastAnnounceAt = DateTime.fromMillisecondsSinceEpoch(0);

  String _format(int v) => widget.percent ? context.l10n.valuePercent(v) : '$v';

  int _clamp(int v) => v.clamp(widget.min, widget.max);

  void _announce(int v) {
    _lastAnnounced = v;
    _lastAnnounceAt = DateTime.now();
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        _format(v),
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  void _adjustBy(int delta) {
    final next = _clamp(widget.value + delta);
    if (next != widget.value) {
      widget.onChanged(next);
      widget.onChangeEnd?.call(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final min = widget.min.toDouble();
    final max = widget.max.toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(widget.label)),
            Expanded(
              flex: 3,
              child: Semantics(
                slider: true,
                value: _format(widget.value),
                increasedValue: _format(_clamp(widget.value + widget.step)),
                decreasedValue: _format(_clamp(widget.value - widget.step)),
                onIncrease: () => _adjustBy(widget.step),
                onDecrease: () => _adjustBy(-widget.step),
                child: ExcludeSemantics(
                  child: Slider(
                    min: min,
                    max: max,
                    value: widget.value.toDouble().clamp(min, max),
                    onChangeStart: (_) {
                      _dragging = true;
                      _lastAnnounced = widget.value;
                    },
                    onChangeEnd: (v) {
                      _dragging = false;
                      final rounded = v.round();
                      if (rounded != _lastAnnounced) _announce(rounded);
                      widget.onChangeEnd?.call(rounded);
                    },
                    onChanged: (v) {
                      final rounded = v.round();
                      if (_dragging &&
                          rounded != _lastAnnounced &&
                          DateTime.now().difference(_lastAnnounceAt) >=
                              _announceInterval) {
                        _announce(rounded);
                      }
                      widget.onChanged(rounded);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
