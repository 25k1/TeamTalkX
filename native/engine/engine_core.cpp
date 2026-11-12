#include "engine_core.h"

#include <cmath>

#include <algorithm>

namespace tt {

namespace {
constexpr size_t kChunk = 4096;
}

EngineCore::EngineCore(int sampleRate, int playbackChannels)
    : sampleRate_(sampleRate),
      channels_(playbackChannels),
      maxQueued_(static_cast<size_t>(sampleRate) * playbackChannels / 2),
      capture_(static_cast<size_t>(sampleRate) * 2),
      mix_(kChunk),
      scratch_(kChunk) {
  speakers_.reserve(kMaxSpeakers);
  for (int i = 0; i < kMaxSpeakers; i++) {
    speakers_.push_back(std::make_unique<Speaker>(maxQueued_ + kChunk));
  }
}

int EngineCore::writeSpeaker(int32_t key, const int16_t* pcm, size_t samples, float gain) {
  if (key < 0) return -1;
  std::lock_guard<std::mutex> lock(writers_);
  Speaker* slot = nullptr;
  for (auto& s : speakers_) {
    if (s->key.load(std::memory_order_acquire) == key) {
      slot = s.get();
      break;
    }
  }
  if (slot == nullptr) {
    for (auto& s : speakers_) {
      if (s->key.load(std::memory_order_acquire) == kFree) {
        slot = s.get();
        break;
      }
    }
    if (slot == nullptr) return -1;
    slot->gain.store(gain, std::memory_order_relaxed);
    slot->key.store(key, std::memory_order_release);
  }
  slot->gain.store(gain, std::memory_order_relaxed);
  const size_t written = slot->ring.write(pcm, samples);
  if (written < samples) {
    speakerDropped_.fetch_add(static_cast<int64_t>(samples - written), std::memory_order_relaxed);
  }
  return static_cast<int>(written);
}

size_t EngineCore::speakerQueued(int32_t key) const {
  if (key < 0) return 0;
  for (const auto& s : speakers_) {
    if (s->key.load(std::memory_order_acquire) == key) return s->ring.available();
  }
  return 0;
}

void EngineCore::removeSpeaker(int32_t key) {
  if (key < 0) return;
  std::lock_guard<std::mutex> lock(writers_);
  for (auto& s : speakers_) {
    if (s->key.load(std::memory_order_acquire) == key) {
      s->key.store(kDraining, std::memory_order_release);
    }
  }
}

void EngineCore::resetSpeakers() {
  std::lock_guard<std::mutex> lock(writers_);
  for (auto& s : speakers_) {
    s->ring.clear();
    s->key.store(kFree, std::memory_order_release);
  }
}

int EngineCore::activeSpeakers() const {
  int n = 0;
  for (const auto& s : speakers_) {
    if (s->key.load(std::memory_order_relaxed) >= 0) n++;
  }
  return n;
}

void EngineCore::render(int16_t* out, size_t frames) {
  size_t remaining = frames * static_cast<size_t>(channels_);
  while (remaining > 0) {
    const size_t n = std::min(remaining, kChunk);
    mixChunk(out, n);
    out += n;
    remaining -= n;
  }
  renderedFrames_.fetch_add(static_cast<int64_t>(frames), std::memory_order_relaxed);
}

void EngineCore::mixChunk(int16_t* out, size_t samples) {
  std::fill(mix_.begin(), mix_.begin() + static_cast<long>(samples), 0);
  for (auto& s : speakers_) {
    const int32_t key = s->key.load(std::memory_order_acquire);
    if (key == kDraining) {
      s->ring.clear();
      s->key.store(kFree, std::memory_order_release);
      continue;
    }
    if (key < 0) continue;
    const size_t dropped = s->ring.trim(maxQueued_);
    if (dropped > 0) {
      speakerDropped_.fetch_add(static_cast<int64_t>(dropped), std::memory_order_relaxed);
    }
    const size_t got = s->ring.read(scratch_.data(), samples);
    const float gain = s->gain.load(std::memory_order_relaxed);
    for (size_t i = 0; i < got; i++) {
      mix_[i] += static_cast<int32_t>(static_cast<float>(scratch_[i]) * gain);
    }
  }
  const float master = masterGain_.load(std::memory_order_relaxed);
  for (size_t i = 0; i < samples; i++) {
    out[i] = softClip(static_cast<float>(mix_[i]) * master);
  }
}

int16_t EngineCore::softClip(float v) {
  constexpr float kFull = 32767.0f;
  constexpr float kKnee = 0.75f * kFull;
  const float a = std::fabs(v);
  if (a <= kKnee) return static_cast<int16_t>(v);
  constexpr float kRoom = kFull - kKnee;
  const float bent = kKnee + kRoom * std::tanh((a - kKnee) / kRoom);
  return static_cast<int16_t>(v < 0 ? -bent : bent);
}

void EngineCore::pushCapture(const int16_t* in, size_t samples) {
  const size_t written = capture_.write(in, samples);
  if (written < samples) {
    captureOverflow_.fetch_add(static_cast<int64_t>(samples - written), std::memory_order_relaxed);
  }
}

}
