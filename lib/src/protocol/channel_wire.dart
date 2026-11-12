library;

import '../domain/models.dart';
import '../domain/tt_types.dart';
import 'command.dart';

const _speexFrameMSec = 20;

int opusFrameSamples(int sampleRate, int msec) {
  final int tenthsOfMSec;
  if (msec < 5) {
    tenthsOfMSec = 25;
  } else if (msec < 10) {
    tenthsOfMSec = 50;
  } else if (msec < 20) {
    tenthsOfMSec = 100;
  } else if (msec < 40) {
    tenthsOfMSec = 200;
  } else if (msec < 60) {
    tenthsOfMSec = 400;
  } else if (msec < 80) {
    tenthsOfMSec = 600;
  } else if (msec < 100) {
    tenthsOfMSec = 800;
  } else if (msec < 120) {
    tenthsOfMSec = 1000;
  } else if (msec == 120) {
    tenthsOfMSec = 1200;
  } else {
    return 0;
  }
  return sampleRate * tenthsOfMSec ~/ 10000;
}

int opusFrameMSec(int sampleRate, int samples) {
  if (sampleRate == 0) return 0;
  final snapped = opusFrameSamples(sampleRate, samples * 1000 ~/ sampleRate);
  return snapped * 1000 ~/ sampleRate;
}

int _speexFramesPerPacket(int txIntervalMSec) {
  var fpp = 1;
  while (fpp * _speexFrameMSec < txIntervalMSec) {
    fpp++;
  }
  return fpp;
}

List<int> audioCodecToWire(TtAudioCodec c) {
  switch (c.codec) {
    case AudioCodecType.opus:
      final int frameSize;
      final int fpp;
      if (c.opusFrameSizeMSec > 0) {
        frameSize = opusFrameSamples(c.opusSampleRate, c.opusFrameSizeMSec);
        final txSamples = c.opusSampleRate * c.opusTxIntervalMSec ~/ 1000;
        fpp = frameSize == 0 ? 1 : txSamples ~/ frameSize;
      } else {
        frameSize = opusFrameSamples(c.opusSampleRate, c.opusTxIntervalMSec);
        fpp = 1;
      }
      return [
        AudioCodecType.opus.value,
        c.opusSampleRate,
        c.opusChannels,
        c.opusApplication,
        c.opusComplexity,
        c.opusFec ? 1 : 0,
        c.opusDtx ? 1 : 0,
        c.opusBitrate,
        c.opusVbr ? 1 : 0,
        c.opusVbrConstraint ? 1 : 0,
        frameSize,
        fpp < 1 ? 1 : fpp,
      ];
    case AudioCodecType.speex:
      return [
        AudioCodecType.speex.value,
        c.speexBandmode,
        c.speexQuality,
        _speexFramesPerPacket(c.speexTxIntervalMSec),
        0,
      ];
    case AudioCodecType.speexVbr:
      return [
        AudioCodecType.speexVbr.value,
        c.speexVbrBandmode,
        c.speexVbrQuality,
        0,
        c.speexVbrMaxBitRate,
        c.speexVbrDtx ? 1 : 0,
        _speexFramesPerPacket(c.speexVbrTxIntervalMSec),
        0,
      ];
    default:
      return [AudioCodecType.none.value];
  }
}

TtAudioCodec audioCodecFromWire(List<int> wire) {
  const base = TtAudioCodec();
  int at(int i, int fallback) => i < wire.length ? wire[i] : fallback;
  switch (AudioCodecType.fromValue(at(0, AudioCodecType.none.value))) {
    case AudioCodecType.opus:
      final sampleRate = at(1, base.opusSampleRate);
      final frameSize = at(10, 0);
      final fpp = at(11, 1);
      return base.copyWith(
        codec: AudioCodecType.opus,
        opusSampleRate: sampleRate,
        opusChannels: at(2, base.opusChannels),
        opusApplication: at(3, base.opusApplication),
        opusComplexity: at(4, base.opusComplexity),
        opusFec: at(5, 1) != 0,
        opusDtx: at(6, 1) != 0,
        opusBitrate: at(7, base.opusBitrate),
        opusVbr: at(8, 1) != 0,
        opusVbrConstraint: at(9, 0) != 0,
        opusFrameSizeMSec: opusFrameMSec(sampleRate, frameSize),
        opusTxIntervalMSec: sampleRate == 0
            ? 0
            : frameSize * fpp * 1000 ~/ sampleRate,
      );
    case AudioCodecType.speex:
      return base.copyWith(
        codec: AudioCodecType.speex,
        speexBandmode: at(1, base.speexBandmode),
        speexQuality: at(2, base.speexQuality),
        speexTxIntervalMSec: at(3, 1) * _speexFrameMSec,
      );
    case AudioCodecType.speexVbr:
      return base.copyWith(
        codec: AudioCodecType.speexVbr,
        speexVbrBandmode: at(1, base.speexVbrBandmode),
        speexVbrQuality: at(2, base.speexVbrQuality),
        speexVbrMaxBitRate: at(4, base.speexVbrMaxBitRate),
        speexVbrDtx: at(5, 1) != 0,
        speexVbrTxIntervalMSec: at(6, 1) * _speexFrameMSec,
      );
    case AudioCodecType.none:
      return base.copyWith(codec: AudioCodecType.none);
  }
}

TtChannelConfig channelConfigFromCommand(TtCommand c, {TtChannelConfig? base}) {
  final b = base ?? const TtChannelConfig(name: '', maxUsers: 0);
  final type = c.getInt('type');
  bool flag(int bit, bool current) => type == null ? current : type & bit != 0;
  final quota = c.getInt('diskquota');
  final audioCfg = c.getIntList('audiocfg');
  final codec = c.getIntList('audiocodec');
  return b.copyWith(
    name: c.getString('name'),
    topic: c.getString('topic'),
    password: c.getString('password'),
    opPassword: c.getString('oppassword'),
    maxUsers: c.getInt('maxusers'),
    diskQuotaKB: quota == null ? null : quota ~/ 1024,
    permanent: flag(ChannelTypes.permanent, b.permanent),
    soloTransmit: flag(ChannelTypes.soloTransmit, b.soloTransmit),
    classroom: flag(ChannelTypes.classroom, b.classroom),
    operatorRecvOnly: flag(ChannelTypes.operatorRecvOnly, b.operatorRecvOnly),
    noVoiceActivation: flag(
      ChannelTypes.noVoiceActivation,
      b.noVoiceActivation,
    ),
    noRecording: flag(ChannelTypes.noRecording, b.noRecording),
    hidden: flag(ChannelTypes.hidden, b.hidden),
    agcEnabled: audioCfg.isNotEmpty ? audioCfg[0] != 0 : null,
    gainLevel: audioCfg.length > 1 ? audioCfg[1] : null,
    codec: codec.isNotEmpty ? audioCodecFromWire(codec) : null,
  );
}

Map<String, Object> channelWireProperties(TtChannelConfig cfg) => {
  'name': cfg.name,
  'password': cfg.password,
  'topic': cfg.topic,
  'diskquota': cfg.diskQuotaKB * 1024,
  'oppassword': cfg.opPassword,
  'maxusers': cfg.maxUsers,
  'audiocodec': audioCodecToWire(cfg.codec),
  'audiocfg': [cfg.agcEnabled ? 1 : 0, cfg.gainLevel],
  'type': cfg.channelTypeMask,
};

TtCommand makeChannelCommand(TtChannelConfig cfg, {required int parentId}) {
  final cmd = TtCommand('makechannel').set('parentid', parentId);
  channelWireProperties(cfg).forEach(cmd.set);
  return cmd.set('userdata', 0);
}

TtCommand updateChannelCommand(
  int channelId,
  TtChannelConfig cfg, {
  TtChannelConfig? current,
}) {
  final cmd = TtCommand('updatechannel').set('chanid', channelId);
  final before = current == null ? null : channelWireProperties(current);
  channelWireProperties(cfg).forEach((key, value) {
    if (before == null || !_sameValue(before[key], value)) cmd.set(key, value);
  });
  return cmd;
}

bool _sameValue(Object? a, Object? b) {
  if (a is List<int> && b is List<int>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}
