import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/foreground_service.dart';
import '../platform_services.dart';
import '../recording/recording_controller.dart';
import 'voice_providers.dart';

final foregroundActionsProvider = Provider<void>((ref) {
  final sub = ref.read(foregroundServiceProvider).actions.listen((action) {
    switch (action) {
      case ForegroundAction.toggleTransmission:
        ref.read(voiceProvider.notifier).toggleTransmission();
      case ForegroundAction.stopRecording:
        unawaited(ref.read(recordingProvider.notifier).stop());
    }
  });
  ref.onDispose(sub.cancel);
});
