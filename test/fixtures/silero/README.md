# Silero reference data

`input.wav` (16 kHz, 16-bit mono) is synthetic: silence, noise, tones,
speech-like vowels, clipping and a DC offset. `expected.json` holds ONNX
Runtime's speech probability for each 512-sample chunk of it, run on the
official Silero VAD v6.2 model with the previous chunk's last 64 samples in
front (as Silero's own code does), and the LSTM state after the last chunk.

`test/native/silero_test.dart` compares the native implementation
(`native/silero_vad.c`, D180) with it; `tool/device/silero_check.dart` does
the same on a phone. Both files are written by `tool/silero/export.py`,
together with `assets/vad/silero_vad_v6_2.bin`.
