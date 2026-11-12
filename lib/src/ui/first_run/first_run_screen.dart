import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/settings/first_run.dart';
import '../../app/settings/settings_providers.dart';
import '../../domain/app_permission.dart';
import '../../l10n/l10n.dart';
import '../common/labels.dart';

class FirstRunScreen extends StatelessWidget {
  const FirstRunScreen({super.key});

  static const stepCount = 8;

  static const routeName = 'setup';

  static void open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const FirstRunScreen(),
    ),
  );

  @override
  Widget build(BuildContext context) => const _Step(index: 0);
}

enum _StepKind {
  language,
  nickname,
  gender,
  speech,
  voiceActivation,
  permissions,
  battery,
  done,
}

class _Step extends ConsumerStatefulWidget {
  const _Step({required this.index});

  final int index;

  @override
  ConsumerState<_Step> createState() => _StepState();
}

class _StepState extends ConsumerState<_Step> {
  final _nickname = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nickname.text = ref.read(settingsProvider).nickname;
  }

  _StepKind get _kind => _StepKind.values[widget.index];
  bool get _last => widget.index == _StepKind.values.length - 1;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(firstRunProvider.notifier).complete();
    Navigator.of(
      context,
    ).popUntil((route) => route.settings.name != FirstRunScreen.routeName);
  }

  void _next() {
    if (_kind == _StepKind.nickname) {
      final nickname = _nickname.text.trim();
      if (nickname.isNotEmpty) {
        ref.read(settingsProvider.notifier).setNickname(nickname);
      }
    }
    if (_last) {
      _finish();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: FirstRunScreen.routeName),
        builder: (_) => _Step(index: widget.index + 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (title, body) = switch (_kind) {
      _StepKind.language => (l10n.setupWelcome, _language(context)),
      _StepKind.nickname => (l10n.setupNicknameTitle, _nicknameStep(context)),
      _StepKind.gender => (l10n.settingsGender, _gender(context)),
      _StepKind.speech => (l10n.setupSpeechTitle, _speech(context)),
      _StepKind.voiceActivation => (
        l10n.settingsVoiceActivation,
        _voiceActivation(context),
      ),
      _StepKind.permissions => (
        l10n.setupPermissionsTitle,
        const _Permissions(
          kinds: [
            AppPermission.microphone,
            AppPermission.notifications,
            AppPermission.phone,
            AppPermission.bluetooth,
          ],
        ),
      ),
      _StepKind.battery => (
        l10n.setupBatteryTitle,
        const _Permissions(kinds: [AppPermission.battery]),
      ),
      _StepKind.done => (l10n.setupDoneTitle, Text(l10n.setupDoneBody)),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.setupStepTitle(
            title,
            widget.index + 1,
            FirstRunScreen.stepCount,
          ),
        ),
        automaticallyImplyLeading: widget.index > 0,
        actions: [
          if (!_last)
            TextButton(onPressed: _finish, child: Text(l10n.setupSkipAll)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: body,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_last ? l10n.setupStart : l10n.setupNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choices<T>({
    required String intro,
    required Map<T, String> options,
    required T selected,
    required void Function(T) onChanged,
    Map<T, String> details = const {},
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(intro),
      const SizedBox(height: 8),
      RadioGroup<T>(
        groupValue: selected,
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
        child: Column(
          children: [
            for (final MapEntry(:key, :value) in options.entries)
              RadioListTile<T>(
                title: Text(value),
                subtitle: details[key] == null ? null : Text(details[key]!),
                value: key,
              ),
          ],
        ),
      ),
    ],
  );

  Widget _language(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    return _choices<AppLanguage>(
      intro: l10n.setupWelcomeBody,
      options: {
        AppLanguage.system: l10n.languageSystem,
        AppLanguage.english: 'English',
        AppLanguage.russian: 'Русский',
        AppLanguage.georgian: 'ქართული',
      },
      selected: settings.language,
      onChanged: ref.read(settingsProvider.notifier).setLanguage,
    );
  }

  Widget _nicknameStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.setupNicknameBody),
        TextField(
          controller: _nickname,
          decoration: InputDecoration(labelText: l10n.commonNickname),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _next(),
        ),
      ],
    );
  }

  Widget _gender(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    return _choices<Gender>(
      intro: l10n.setupGenderBody,
      options: {for (final g in Gender.values) g: g.label(l10n)},
      selected: settings.gender,
      onChanged: ref.read(settingsProvider.notifier).setGender,
    );
  }

  Widget _speech(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    return _choices<SpeechOutput>(
      intro: l10n.setupSpeechBody,
      options: {
        SpeechOutput.screenReader: l10n.speechScreenReader,
        SpeechOutput.tts: l10n.speechTts,
        SpeechOutput.none: l10n.speechNothing,
      },
      details: {
        SpeechOutput.screenReader: l10n.speechScreenReaderSub,
        SpeechOutput.tts: l10n.setupSpeechTtsSub,
        SpeechOutput.none: l10n.setupSpeechNoneSub,
      },
      selected: settings.speechOutput,
      onChanged: ref.read(settingsProvider.notifier).setSpeechOutput,
    );
  }

  Widget _voiceActivation(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    return _choices<VadEngine>(
      intro: l10n.setupVoxBody,
      options: {for (final e in VadEngine.values) e: e.label},
      details: {
        VadEngine.rnnoise: l10n.setupVoxRnnoise,
        VadEngine.silero: l10n.setupVoxSilero,
      },
      selected: settings.vadEngine,
      onChanged: ref.read(settingsProvider.notifier).setVadEngine,
    );
  }
}

class _Permissions extends ConsumerStatefulWidget {
  const _Permissions({required this.kinds});

  final List<AppPermission> kinds;

  @override
  ConsumerState<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends ConsumerState<_Permissions> {
  final _granted = <AppPermission, bool>{};

  @override
  void initState() {
    super.initState();
    for (final kind in widget.kinds) {
      ref.read(permissionsProvider).isGranted(kind).then((granted) {
        if (mounted) setState(() => _granted[kind] = granted);
      }).ignore();
    }
  }

  Future<void> _request(AppPermission kind) async {
    final granted = await ref.read(permissionsProvider).request(kind);
    if (mounted) setState(() => _granted[kind] = granted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.kinds.contains(AppPermission.battery)
              ? l10n.setupBatteryBody
              : l10n.setupPermissionsBody,
        ),
        for (final kind in widget.kinds)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(kind.label(l10n)),
            subtitle: Text(kind.reason(l10n)),
            trailing: _granted[kind] ?? false
                ? Text(l10n.setupAllowed)
                : TextButton(
                    onPressed: () => _request(kind),
                    child: Text(l10n.setupAllow),
                  ),
          ),
      ],
    );
  }
}
