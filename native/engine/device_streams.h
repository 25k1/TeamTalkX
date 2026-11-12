#ifndef TT_DEVICE_STREAMS_H
#define TT_DEVICE_STREAMS_H

#ifdef __ANDROID__

#include <oboe/Oboe.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <thread>

#include "engine_core.h"

namespace tt {

class DeviceStreams : public oboe::AudioStreamDataCallback,
                      public oboe::AudioStreamErrorCallback {
 public:
  explicit DeviceStreams(EngineCore& core) : core_(core) {}
  ~DeviceStreams() override;

  int startPlayback();
  void startPlaybackAsync();
  void stopPlayback();
  int startCapture(int inputPreset, int sampleRate, int channels);
  void stopCapture();

  void setOutput(bool voiceCall, int deviceId);

  struct Info {
    bool running = false;
    int sampleRate = 0;
    int channels = 0;
    int burstFrames = 0;
    int bufferFrames = 0;
    int xruns = 0;
    double latencyMs = -1;
  };
  Info playbackInfo();
  Info captureInfo();
  int lastError() const { return lastError_.load(std::memory_order_relaxed); }

  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* stream, void* audioData,
                                        int32_t numFrames) override;
  void onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) override;

 private:
  int openPlaybackLocked();
  int openCaptureLocked();
  Info infoOf(const std::shared_ptr<oboe::AudioStream>& stream);

  EngineCore& core_;
  std::mutex mutex_;
  std::shared_ptr<oboe::AudioStream> playback_;
  std::shared_ptr<oboe::AudioStream> capture_;
  bool wantPlayback_ = false;
  bool opening_ = false;
  std::thread opener_;
  bool wantCapture_ = false;
  int inputPreset_ = 7;
  bool voiceCall_ = false;
  int deviceId_ = 0;
  int captureRate_ = 48000;
  int captureChannels_ = 1;
  std::atomic<int> lastError_{0};
};

}

#endif
#endif
