import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/channels/channel_tree_providers.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';
import '../common/unsaved_changes.dart';
import '../settings/settings_widgets.dart';

class ChannelEditScreen extends ConsumerStatefulWidget {
  const ChannelEditScreen.create({super.key, required int this.parentId})
    : channelId = null;

  const ChannelEditScreen.edit({super.key, required int this.channelId})
    : parentId = null;

  final int? parentId;
  final int? channelId;

  @override
  ConsumerState<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends ConsumerState<ChannelEditScreen>
    with TextControllers, UnsavedChanges {
  @override
  List<Object?> get formValues => [
    _permanent,
    _hidden,
    _noVoiceActivation,
    _noRecording,
    _classroom,
    _operatorRecvOnly,
    _soloTransmit,
    _agc,
    _codec,
    _opusSampleRate,
    _opusChannels,
    _opusApplication,
    _opusFrameSize,
    _opusVbr,
    _opusDtx,
    _speexBandmode,
    _speexVbrBandmode,
    _speexVbrDtx,
  ];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _topic;
  late final TextEditingController _password;
  late final TextEditingController _opPassword;
  late final TextEditingController _maxUsers;
  late final TextEditingController _diskQuota;
  late final TextEditingController _gainLevel;
  late final TextEditingController _opusBitrate;
  late final TextEditingController _opusTx;
  late final TextEditingController _speexQuality;
  late final TextEditingController _speexTx;
  late final TextEditingController _speexVbrQuality;
  late final TextEditingController _speexVbrMaxBitrate;
  late final TextEditingController _speexVbrTx;

  bool _permanent = false;
  bool _hidden = false;
  bool _noVoiceActivation = false;
  bool _noRecording = false;
  bool _classroom = false;
  bool _operatorRecvOnly = false;
  bool _soloTransmit = false;

  bool _agc = true;

  AudioCodecType _codec = AudioCodecType.opus;
  int _opusSampleRate = 48000;
  int _opusChannels = 1;
  int _opusApplication = TtAudioCodec.opusApplicationVoip;
  int _opusFrameSize = 40;
  bool _opusVbr = true;
  bool _opusDtx = true;
  int _speexBandmode = 1;
  int _speexVbrBandmode = 1;
  bool _speexVbrDtx = true;

  late TtAudioCodec _baseCodec;

  bool get _isEdit => widget.channelId != null;

  @override
  void initState() {
    super.initState();
    final client = ref.read(teamTalkClientProvider);
    final cfg = _isEdit
        ? client.getChannelConfig(widget.channelId!)
        : TtChannelConfig(name: '', maxUsers: client.serverMaxUsers);

    _name = textController(cfg.name);
    _topic = textController(cfg.topic);
    _password = textController(cfg.password);
    _opPassword = textController(cfg.opPassword);
    _maxUsers = textController('${cfg.maxUsers}');
    _diskQuota = textController('${cfg.diskQuotaKB}');
    _gainLevel = textController('${cfg.gainLevel}');
    _permanent = cfg.permanent;
    _hidden = cfg.hidden;
    _noVoiceActivation = cfg.noVoiceActivation;
    _noRecording = cfg.noRecording;
    _classroom = cfg.classroom;
    _operatorRecvOnly = cfg.operatorRecvOnly;
    _soloTransmit = cfg.soloTransmit;
    _agc = cfg.agcEnabled;

    final c = cfg.codec;
    _baseCodec = c;
    _codec = c.codec;
    _opusSampleRate = c.opusSampleRate;
    _opusChannels = c.opusChannels;
    _opusApplication = c.opusApplication;
    _opusFrameSize = c.opusFrameSizeMSec;
    _opusVbr = c.opusVbr;
    _opusDtx = c.opusDtx;
    _opusBitrate = textController('${c.opusBitrate ~/ 1000}');
    _opusTx = textController('${c.opusTxIntervalMSec}');
    _speexBandmode = c.speexBandmode;
    _speexQuality = textController('${c.speexQuality}');
    _speexTx = textController('${c.speexTxIntervalMSec}');
    _speexVbrBandmode = c.speexVbrBandmode;
    _speexVbrQuality = textController('${c.speexVbrQuality}');
    _speexVbrMaxBitrate = textController('${c.speexVbrMaxBitRate}');
    _speexVbrDtx = c.speexVbrDtx;
    _speexVbrTx = textController('${c.speexVbrTxIntervalMSec}');
    markSaved();
  }

  TtAudioCodec _buildCodec() {
    return switch (_codec) {
      AudioCodecType.opus => _baseCodec.copyWith(
        codec: AudioCodecType.opus,
        opusSampleRate: _opusSampleRate,
        opusChannels: _opusChannels,
        opusApplication: _opusApplication,
        opusBitrate: _opusBitrateFromField(),
        opusVbr: _opusVbr,
        opusDtx: _opusDtx,
        opusTxIntervalMSec: intFromField(_opusTx, 40),
        opusFrameSizeMSec: _opusFrameSize,
      ),
      AudioCodecType.speex => _baseCodec.copyWith(
        codec: AudioCodecType.speex,
        speexBandmode: _speexBandmode,
        speexQuality: intFromField(_speexQuality, 4),
        speexTxIntervalMSec: intFromField(_speexTx, 40),
      ),
      AudioCodecType.speexVbr => _baseCodec.copyWith(
        codec: AudioCodecType.speexVbr,
        speexVbrBandmode: _speexVbrBandmode,
        speexVbrQuality: intFromField(_speexVbrQuality, 4),
        speexVbrMaxBitRate: intFromField(_speexVbrMaxBitrate, 0),
        speexVbrDtx: _speexVbrDtx,
        speexVbrTxIntervalMSec: intFromField(_speexVbrTx, 40),
      ),
      _ => _baseCodec.copyWith(codec: AudioCodecType.none),
    };
  }

  int _opusBitrateFromField() {
    final kbps = intFromField(_opusBitrate, 32);
    return kbps == _baseCodec.opusBitrate ~/ 1000
        ? _baseCodec.opusBitrate
        : kbps * 1000;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final client = ref.read(teamTalkClientProvider);
    final cfg = TtChannelConfig(
      name: _name.text.trim(),
      topic: _topic.text.trim(),
      password: _password.text,
      opPassword: _opPassword.text,
      maxUsers: intFromField(_maxUsers, client.serverMaxUsers),
      diskQuotaKB: intFromField(_diskQuota, 0),
      permanent: _permanent,
      hidden: _hidden,
      noVoiceActivation: _noVoiceActivation,
      noRecording: _noRecording,
      classroom: _classroom,
      operatorRecvOnly: _operatorRecvOnly,
      soloTransmit: _soloTransmit,
      agcEnabled: _agc,
      gainLevel: intFromField(_gainLevel, 8000),
      codec: _buildCodec(),
    );
    try {
      await client.saveChannel(
        cfg,
        parentId: widget.parentId,
        channelId: widget.channelId,
      );
      if (!_isEdit && widget.parentId != null) {
        ref.read(expandedChannelProvider.notifier).expand(widget.parentId!);
      }
      final saved = ref.read(appLocalizationsProvider).channelSaved(cfg.name);
      messenger.showMessage(saved);
      ref.read(announcerProvider).announceShown(saved);
      navigator.pop();
    } on Object catch (e, st) {
      appLog.w('channels', 'Saving channel failed', e, st);
      reportFailure(ref, messenger, action: (l) => l.actionSave, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return guardUnsaved(
      save: _save,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? l10n.channelEdit : l10n.channelEditCreate),
          actions: [TextButton(onPressed: _save, child: Text(l10n.commonSave))],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            children: [
              SectionHeader(l10n.settingsGeneral),
              _text(
                _name,
                l10n.channelEditName,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.channelEditNameRequired
                    : null,
              ),
              _text(_topic, l10n.channelEditTopicOptional),
              _text(
                _password,
                _isEdit
                    ? l10n.channelEditPasswordRemoves
                    : l10n.serverEditPasswordOptional,
                obscure: true,
              ),
              _text(
                _opPassword,
                l10n.channelEditOpPasswordOptional,
                obscure: true,
              ),
              _text(_maxUsers, l10n.channelEditMaxUsers, number: true),
              _text(_diskQuota, l10n.channelEditDiskQuota, number: true),
              SectionHeader(l10n.channelEditType),
              _switch(
                l10n.channelTypePermanent,
                _permanent,
                (v) => _permanent = v,
                subtitle: l10n.channelEditPermanentSub,
              ),
              _switch(
                l10n.channelTypeHidden,
                _hidden,
                (v) => _hidden = v,
                subtitle: l10n.channelEditHiddenSub,
              ),
              _switch(
                l10n.channelTypeNoVoiceActivation,
                _noVoiceActivation,
                (v) => _noVoiceActivation = v,
              ),
              _switch(
                l10n.channelTypeNoRecording,
                _noRecording,
                (v) => _noRecording = v,
              ),
              _switch(
                l10n.channelTypeClassroom,
                _classroom,
                (v) => _classroom = v,
                subtitle: l10n.channelEditClassroomSub,
              ),
              _switch(
                l10n.channelEditOperatorsHearAll,
                _operatorRecvOnly,
                (v) => _operatorRecvOnly = v,
              ),
              _switch(
                l10n.channelTypeSoloTransmit,
                _soloTransmit,
                (v) => _soloTransmit = v,
                subtitle: l10n.channelEditSoloSub,
              ),
              SectionHeader(l10n.channelEditCodec),
              _codecDropdown(l10n),
              ..._codecFields(l10n),
              SectionHeader(l10n.channelEditAudioConfig),
              _switch(
                l10n.audioAgc,
                _agc,
                (v) => _agc = v,
                subtitle: l10n.channelEditAgcSub,
              ),
              if (_agc)
                _text(_gainLevel, l10n.channelEditGainLevel, number: true),
            ],
          ),
        ),
      ),
    );
  }

  Map<int, String> _speexBands(AppLocalizations l10n) => {
    0: l10n.channelEditNarrowBand(l10n.unitKhz('8')),
    1: l10n.channelEditWideBand(l10n.unitKhz('16')),
    2: l10n.channelEditUltraWideBand(l10n.unitKhz('32')),
  };

  List<Widget> _codecFields(AppLocalizations l10n) {
    switch (_codec) {
      case AudioCodecType.opus:
        return [
          _dropdown<int>(l10n.audioSampleRate, _opusSampleRate, {
            for (final rate in const [8000, 12000, 16000, 24000, 48000])
              rate: l10n.unitKhz('${rate ~/ 1000}'),
          }, (v) => setState(() => _opusSampleRate = v)),
          _dropdown<int>(l10n.audioChannels, _opusChannels, {
            1: l10n.audioMono,
            2: l10n.audioStereo,
          }, (v) => setState(() => _opusChannels = v)),
          _dropdown<int>(l10n.channelEditApplication, _opusApplication, {
            TtAudioCodec.opusApplicationVoip: l10n.channelEditVoip,
            TtAudioCodec.opusApplicationAudio: l10n.channelEditMusic,
          }, (v) => setState(() => _opusApplication = v)),
          _text(_opusBitrate, l10n.channelEditBitrate, number: true),
          _switch(l10n.channelEditVbr, _opusVbr, (v) => _opusVbr = v),
          _switch(l10n.channelEditDtx, _opusDtx, (v) => _opusDtx = v),
          _text(_opusTx, l10n.channelEditTxInterval, number: true),
          _dropdown<int>(l10n.channelEditFrameSize, _opusFrameSize, {
            0: l10n.channelEditAuto,
            2: l10n.unitMs('2.5'),
            for (final ms in const [5, 10, 20, 40, 60, 80, 100, 120])
              ms: l10n.unitMs('$ms'),
          }, (v) => setState(() => _opusFrameSize = v)),
        ];
      case AudioCodecType.speex:
        return [
          _dropdown<int>(
            l10n.audioSampleRate,
            _speexBandmode,
            _speexBands(l10n),
            (v) => setState(() => _speexBandmode = v),
          ),
          _text(_speexQuality, l10n.channelEditQuality, number: true),
          _text(_speexTx, l10n.channelEditTxInterval, number: true),
        ];
      case AudioCodecType.speexVbr:
        return [
          _dropdown<int>(
            l10n.audioSampleRate,
            _speexVbrBandmode,
            _speexBands(l10n),
            (v) => setState(() => _speexVbrBandmode = v),
          ),
          _text(_speexVbrQuality, l10n.channelEditQuality, number: true),
          _text(_speexVbrMaxBitrate, l10n.channelEditMaxBitrate, number: true),
          _switch(l10n.channelEditDtx, _speexVbrDtx, (v) => _speexVbrDtx = v),
          _text(_speexVbrTx, l10n.channelEditTxInterval, number: true),
        ];
      default:
        return const [];
    }
  }

  Widget _codecDropdown(AppLocalizations l10n) =>
      _dropdown<AudioCodecType>(l10n.channelEditCodecField, _codec, {
        AudioCodecType.opus: 'OPUS',
        AudioCodecType.speex: 'Speex',
        AudioCodecType.speexVbr: l10n.channelEditSpeexVbr,
        AudioCodecType.none: l10n.channelEditNoAudio,
      }, (v) => setState(() => _codec = v));

  Widget _text(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool obscure = false,
    String? Function(String?)? validator,
  }) => LabeledTextField(
    controller: controller,
    label: label,
    number: number,
    obscure: obscure,
    validator: validator,
  );

  Widget _switch(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: (v) => setState(() => onChanged(v)),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          if (!options.containsKey(value))
            DropdownMenuItem(value: value, child: Text('$value')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
