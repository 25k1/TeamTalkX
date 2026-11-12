import 'dart:ffi';
import 'dart:io';

const nativeLibraryOverride = String.fromEnvironment('TT_NATIVE_LIB');

DynamicLibrary openNativeAudio([String? libraryPath]) {
  final path =
      libraryPath ??
      (nativeLibraryOverride.isNotEmpty ? nativeLibraryOverride : null);
  if (path != null) return DynamicLibrary.open(path);
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libtt_audio.so');
  }
  if (Platform.isWindows) return DynamicLibrary.open('tt_audio.dll');
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('libtt_audio.dylib');
  }
  throw UnsupportedError('No native audio library for this platform');
}
