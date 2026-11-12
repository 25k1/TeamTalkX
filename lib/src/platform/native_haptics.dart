import 'native_channel.dart';

abstract interface class Haptics {
  Future<bool> waveform(List<int> timings, List<int> amplitudes);
}

class AndroidHaptics implements Haptics {
  final _channel = NativeChannel('haptics');

  @override
  Future<bool> waveform(List<int> timings, List<int> amplitudes) async =>
      await _channel.invokeQuiet<bool>('waveform', {
        'timings': timings,
        'amplitudes': amplitudes,
      }) ??
      false;
}
