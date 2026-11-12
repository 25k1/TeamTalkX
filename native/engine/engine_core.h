#ifndef TT_ENGINE_CORE_H
#define TT_ENGINE_CORE_H

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

#include "ring.h"

namespace tt {

class EngineCore {
 public:
  static constexpr int kMaxSpeakers = 32;

  EngineCore(int sampleRate, int playbackChannels);

  int sampleRate() const { return sampleRate_; }
  int playbackChannels() const { return channels_; }

  int writeSpeaker(int32_t key, const int16_t* pcm, size_t samples, float gain);

  size_t speakerQueued(int32_t key) const;

  void removeSpeaker(int32_t key);

  void setMasterGain(float gain) { masterGain_.store(gain, std::memory_order_relaxed); }

  size_t readCapture(int16_t* out, size_t max) { return capture_.read(out, max); }

  void resetSpeakers();

  void clearCapture() { capture_.clear(); }

  void render(int16_t* out, size_t frames);

  void pushCapture(const int16_t* in, size_t samples);

  int activeSpeakers() const;
  int64_t speakerDropped() const { return speakerDropped_.load(std::memory_order_relaxed); }
  int64_t captureOverflow() const { return captureOverflow_.load(std::memory_order_relaxed); }
  int64_t renderedFrames() const { return renderedFrames_.load(std::memory_order_relaxed); }

 private:
  static constexpr int32_t kFree = -1;
  static constexpr int32_t kDraining = -2;

  struct Speaker {
    explicit Speaker(size_t capacity) : ring(capacity) {}
    std::atomic<int32_t> key{kFree};
    std::atomic<float> gain{1.0f};
    Ring ring;
  };

  void mixChunk(int16_t* out, size_t samples);
  static int16_t softClip(float v);

  const int sampleRate_;
  const int channels_;
  const size_t maxQueued_;
  std::vector<std::unique_ptr<Speaker>> speakers_;
  std::mutex writers_;
  std::atomic<float> masterGain_{1.0f};
  Ring capture_;
  std::vector<int32_t> mix_;
  std::vector<int16_t> scratch_;
  std::atomic<int64_t> speakerDropped_{0};
  std::atomic<int64_t> captureOverflow_{0};
  std::atomic<int64_t> renderedFrames_{0};
};

}

#endif
