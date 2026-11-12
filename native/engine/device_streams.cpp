#ifdef __ANDROID__

#include "device_streams.h"

#include <android/log.h>

namespace tt {

namespace {

constexpr const char* kTag = "tt_audio";

oboe::InputPreset inputPresetFor(int audioSource) {
  switch (audioSource) {
    case 0:
    case 1:
      return oboe::InputPreset::Generic;
    case 5:
      return oboe::InputPreset::Camcorder;
    case 6:
      return oboe::InputPreset::VoiceRecognition;
    case 9:
      return oboe::InputPreset::Unprocessed;
    case 10:
      return oboe::InputPreset::VoicePerformance;
    case 7:
    default:
      return oboe::InputPreset::VoiceCommunication;
  }
}

}

DeviceStreams::~DeviceStreams() {
  stopCapture();
  stopPlayback();
  if (opener_.joinable()) opener_.join();
}

int DeviceStreams::startPlayback() {
  std::lock_guard<std::mutex> lock(mutex_);
  wantPlayback_ = true;
  if (playback_) return 0;
  return openPlaybackLocked();
}

void DeviceStreams::startPlaybackAsync() {
  std::lock_guard<std::mutex> lock(mutex_);
  wantPlayback_ = true;
  if (playback_ || opening_) return;
  opening_ = true;
  if (opener_.joinable()) opener_.join();
  opener_ = std::thread([this] {
    std::lock_guard<std::mutex> lock(mutex_);
    if (wantPlayback_ && !playback_) openPlaybackLocked();
    opening_ = false;
  });
}

int DeviceStreams::openPlaybackLocked() {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Output)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Exclusive)
      ->setFormat(oboe::AudioFormat::I16)
      ->setChannelCount(core_.playbackChannels())
      ->setSampleRate(core_.sampleRate())
      ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
      ->setUsage(voiceCall_ ? oboe::Usage::VoiceCommunication : oboe::Usage::Game)
      ->setContentType(oboe::ContentType::Speech)
      ->setDeviceId(deviceId_)
      ->setDataCallback(this)
      ->setErrorCallback(this);
  const oboe::Result result = builder.openStream(playback_);
  if (result != oboe::Result::OK) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "Playback stream failed to open: %s",
                        oboe::convertToText(result));
    lastError_.store(static_cast<int>(result), std::memory_order_relaxed);
    playback_.reset();
    return static_cast<int>(result);
  }
  playback_->setBufferSizeInFrames(playback_->getFramesPerBurst() * 2);
  const oboe::Result started = playback_->requestStart();
  if (started != oboe::Result::OK) {
    lastError_.store(static_cast<int>(started), std::memory_order_relaxed);
    playback_->close();
    playback_.reset();
    return static_cast<int>(started);
  }
  return 0;
}

void DeviceStreams::stopPlayback() {
  std::shared_ptr<oboe::AudioStream> stream;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    wantPlayback_ = false;
    stream = std::move(playback_);
  }
  if (stream) {
    stream->stop();
    stream->close();
  }
  core_.resetSpeakers();
}

int DeviceStreams::startCapture(int inputPreset, int sampleRate, int channels) {
  std::lock_guard<std::mutex> lock(mutex_);
  wantCapture_ = true;
  if (capture_ && inputPreset == inputPreset_ && sampleRate == captureRate_ &&
      channels == captureChannels_) {
    return 0;
  }
  if (capture_) {
    capture_->stop();
    capture_->close();
    capture_.reset();
  }
  inputPreset_ = inputPreset;
  captureRate_ = sampleRate;
  captureChannels_ = channels;
  core_.clearCapture();
  return openCaptureLocked();
}

int DeviceStreams::openCaptureLocked() {
  oboe::AudioStreamBuilder builder;
  builder.setDirection(oboe::Direction::Input)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Shared)
      ->setFormat(oboe::AudioFormat::I16)
      ->setChannelCount(captureChannels_)
      ->setSampleRate(captureRate_)
      ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
      ->setInputPreset(voiceCall_ ? oboe::InputPreset::VoiceCommunication
                                  : inputPresetFor(inputPreset_))
      ->setDataCallback(this)
      ->setErrorCallback(this);
  const oboe::Result result = builder.openStream(capture_);
  if (result != oboe::Result::OK) {
    __android_log_print(ANDROID_LOG_ERROR, kTag, "Capture stream failed to open: %s",
                        oboe::convertToText(result));
    lastError_.store(static_cast<int>(result), std::memory_order_relaxed);
    capture_.reset();
    return static_cast<int>(result);
  }
  const oboe::Result started = capture_->requestStart();
  if (started != oboe::Result::OK) {
    lastError_.store(static_cast<int>(started), std::memory_order_relaxed);
    capture_->close();
    capture_.reset();
    return static_cast<int>(started);
  }
  return 0;
}

void DeviceStreams::setOutput(bool voiceCall, int deviceId) {
  std::shared_ptr<oboe::AudioStream> oldPlayback;
  std::shared_ptr<oboe::AudioStream> oldCapture;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (voiceCall == voiceCall_ && deviceId == deviceId_) return;
    const bool modeChanged = voiceCall != voiceCall_;
    voiceCall_ = voiceCall;
    deviceId_ = deviceId;
    oldPlayback = std::move(playback_);
    if (modeChanged) oldCapture = std::move(capture_);
  }
  for (auto& stream : {oldPlayback, oldCapture}) {
    if (stream) {
      stream->stop();
      stream->close();
    }
  }
  std::lock_guard<std::mutex> lock(mutex_);
  if (wantPlayback_ && !playback_) openPlaybackLocked();
  if (wantCapture_ && !capture_) openCaptureLocked();
}

void DeviceStreams::stopCapture() {
  std::shared_ptr<oboe::AudioStream> stream;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    wantCapture_ = false;
    stream = std::move(capture_);
  }
  if (stream) {
    stream->stop();
    stream->close();
  }
}

oboe::DataCallbackResult DeviceStreams::onAudioReady(oboe::AudioStream* stream, void* audioData,
                                                     int32_t numFrames) {
  auto* samples = static_cast<int16_t*>(audioData);
  if (stream->getDirection() == oboe::Direction::Output) {
    core_.render(samples, static_cast<size_t>(numFrames));
  } else {
    core_.pushCapture(samples, static_cast<size_t>(numFrames) *
                                   static_cast<size_t>(stream->getChannelCount()));
  }
  return oboe::DataCallbackResult::Continue;
}

void DeviceStreams::onErrorAfterClose(oboe::AudioStream* stream, oboe::Result error) {
  __android_log_print(ANDROID_LOG_WARN, kTag, "Stream closed: %s; reopening",
                      oboe::convertToText(error));
  lastError_.store(static_cast<int>(error), std::memory_order_relaxed);
  const bool output = stream->getDirection() == oboe::Direction::Output;
  std::lock_guard<std::mutex> lock(mutex_);
  if (output) {
    if (playback_.get() != stream) return;
    playback_.reset();
    if (wantPlayback_) openPlaybackLocked();
  } else {
    if (capture_.get() != stream) return;
    capture_.reset();
    if (wantCapture_) openCaptureLocked();
  }
}

DeviceStreams::Info DeviceStreams::infoOf(const std::shared_ptr<oboe::AudioStream>& stream) {
  Info info;
  if (!stream) return info;
  info.running = stream->getState() == oboe::StreamState::Started;
  info.sampleRate = stream->getSampleRate();
  info.channels = stream->getChannelCount();
  info.burstFrames = stream->getFramesPerBurst();
  info.bufferFrames = stream->getBufferSizeInFrames();
  const auto xruns = stream->getXRunCount();
  info.xruns = xruns ? xruns.value() : 0;
  const auto latency = stream->calculateLatencyMillis();
  info.latencyMs = latency ? latency.value() : -1;
  return info;
}

DeviceStreams::Info DeviceStreams::playbackInfo() {
  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) return Info{};
  return infoOf(playback_);
}

DeviceStreams::Info DeviceStreams::captureInfo() {
  std::unique_lock<std::mutex> lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) return Info{};
  return infoOf(capture_);
}

}

#endif
