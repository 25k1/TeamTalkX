part of 'main_screen.dart';

class _StatusDialog extends ConsumerStatefulWidget {
  const _StatusDialog();

  @override
  ConsumerState<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends ConsumerState<_StatusDialog>
    with TextControllers {
  late final TextEditingController _message;
  late UserStatus _status;

  @override
  void initState() {
    super.initState();
    final state = ref.read(teamTalkClientProvider).state;
    final me = state.users[state.myUserId];
    final profileSettings = ref.read(profileSettingsProvider);
    _message = textController(
      me?.statusMessage ?? profileSettings.statusMessage,
    );
    _status = me != null
        ? UserStatus.fromMode(me.statusMode)
        : profileSettings.status;
  }

  Future<void> _apply() async {
    final navigator = Navigator.of(context);
    final client = ref.read(teamTalkClientProvider);
    final message = _message.text.trim();
    final me = client.state.users[client.state.myUserId];
    final genderBits =
        (me?.statusMode ??
            ref.read(profileSettingsProvider).gender.statusBits) &
        ~TtStatusMode.modeMask;
    final mode = genderBits | _status.statusBits;
    ref.read(profileSettingsProvider.notifier).setStatus(_status);
    ref.read(profileSettingsProvider.notifier).setStatusMessage(message);
    try {
      await client.changeStatus(mode, message);
    } on Object catch (e, st) {
      appLog.w('status', 'Changing status failed', e, st);
    }
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.statusChange),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<UserStatus>(
              groupValue: _status,
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final status in UserStatus.values)
                    RadioListTile<UserStatus>(
                      title: Text(status.label(l10n)),
                      value: status,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _message,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.statusMessage),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _apply, child: Text(l10n.commonApply)),
      ],
    );
  }
}

class _VoiceControlsBar extends ConsumerWidget {
  const _VoiceControlsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(serverStateTickProvider);
    final voice = ref.watch(voiceProvider);
    final notifier = ref.read(voiceProvider.notifier);
    final client = ref.watch(teamTalkClientProvider);
    final inChannel = client.state.joinedChannelId > 0;

    final l10n = context.l10n;
    final settings = AccessibleIconButton(
      icon: Icons.tune,
      label: l10n.controlsAudioSettings,
      onPressed: () => pushScreen(context, const AudioSettingsScreen()),
    );
    final voiceActivation = MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(l10n.controlsVoiceActivation)),
          Switch(
            value: voice.voxEnabled,
            onChanged: inChannel
                ? (value) => notifier.setVoiceActivation(enabled: value)
                : null,
          ),
        ],
      ),
    );
    final ptt = _PttButton(enabled: inChannel);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _fitsOneRow(context, constraints.maxWidth)
                ? ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Row(
                      children: [
                        settings,
                        voiceActivation,
                        const SizedBox(width: 12),
                        Expanded(child: ptt),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          settings,
                          Flexible(child: voiceActivation),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ptt,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  static bool _fitsOneRow(BuildContext context, double width) {
    final l10n = context.l10n;
    final style = DefaultTextStyle.of(context).style;
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final pttStyle = style.merge(_PttButtonState.labelStyle);
    final pttLabel = math.max(
      textWidth(l10n.controlsTransmitting, pttStyle),
      textWidth(l10n.controlsTransmitInactive, pttStyle),
    );
    const settingsButton = kMinInteractiveDimension;
    const switchWidth = 60.0;
    const gap = 12.0;
    final needed =
        settingsButton +
        textWidth(l10n.controlsVoiceActivation, style) +
        switchWidth +
        gap +
        _PttButtonState.decorationWidth +
        pttLabel;
    return needed <= width;
  }
}

class _PttButton extends ConsumerStatefulWidget {
  const _PttButton({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends ConsumerState<_PttButton> {
  static const _lockDragThreshold = 56.0;

  static const labelStyle = TextStyle(fontWeight: FontWeight.bold);
  static const _padding = 12.0;
  static const _iconSize = 20.0;
  static const _iconGap = 8.0;

  static const decorationWidth = 2 * _padding + _iconSize + _iconGap;

  double _pressStartY = 0;
  bool _pressConsumed = false;

  bool _a11yFocused = false;
  String? _frozenValue;

  VoiceNotifier get _voice => ref.read(voiceProvider.notifier);

  String _stateValue() {
    final v = ref.read(voiceProvider);
    final l10n = ref.read(appLocalizationsProvider);
    return v.txEnabled || (v.voxEnabled && v.voxActive)
        ? l10n.controlsTransmitting
        : l10n.controlsTransmitInactive;
  }

  void _onGainA11yFocus() => setState(() {
    _frozenValue = _stateValue();
    _a11yFocused = true;
  });

  void _onLoseA11yFocus() => setState(() => _a11yFocused = false);

  void _toggleLock() {
    if (ref.read(voiceProvider).txLocked) {
      _voice.stopTransmission();
    } else {
      _voice.startTransmission();
      _voice.lockTransmission();
    }
  }

  void _onDown(Offset pos) {
    if (!widget.enabled) return;
    if (ref.read(voiceProvider).txLocked) {
      _voice.stopTransmission();
      _pressConsumed = true;
      return;
    }
    _pressConsumed = false;
    _pressStartY = pos.dy;
    _voice.startTransmission();
  }

  void _onMove(Offset pos) {
    if (!widget.enabled || _pressConsumed) return;
    if (!ref.read(voiceProvider).txLocked &&
        _pressStartY - pos.dy > _lockDragThreshold) {
      _voice.lockTransmission();
    }
  }

  void _onUp() {
    if (!widget.enabled) return;
    if (_pressConsumed) {
      _pressConsumed = false;
      return;
    }
    if (ref.read(voiceProvider).txLocked) return;
    _voice.stopTransmission();
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceProvider);
    final locked = voice.txLocked;
    final txOn = voice.txEnabled || (voice.voxEnabled && voice.voxActive);
    final visual = _visual(context, txOn: txOn, locked: locked);
    final label = _a11yFocused
        ? (_frozenValue ?? _stateValue())
        : _stateValue();

    return Semantics(
      key: ValueKey(locked),
      label: label,
      hint: widget.enabled ? null : context.l10n.controlsJoinChannelFirst,
      button: true,
      excludeSemantics: true,
      onDidGainAccessibilityFocus: _onGainA11yFocus,
      onDidLoseAccessibilityFocus: _onLoseA11yFocus,
      customSemanticsActions: widget.enabled
          ? {
              CustomSemanticsAction(
                label: locked
                    ? context.l10n.controlsUnlockTransmission
                    : context.l10n.controlsLockTransmission,
              ): _toggleLock,
            }
          : null,
      child: Listener(
        onPointerDown: (e) => _onDown(e.localPosition),
        onPointerMove: (e) => _onMove(e.localPosition),
        onPointerUp: (e) => _onUp(),
        onPointerCancel: (e) => _onUp(),
        child: visual,
      ),
    );
  }

  Widget _visual(
    BuildContext context, {
    required bool txOn,
    required bool locked,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = !widget.enabled
        ? scheme.surfaceContainerHighest
        : (txOn ? Colors.green : Colors.red);
    final fg = widget.enabled ? Colors.white : scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: _padding),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? Icons.lock : (txOn ? Icons.mic : Icons.mic_off),
            color: fg,
            size: _iconSize,
          ),
          const SizedBox(width: _iconGap),
          Flexible(
            child: Text(
              txOn
                  ? context.l10n.controlsTransmitting
                  : context.l10n.controlsTransmitInactive,
              style: labelStyle.copyWith(color: fg),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
