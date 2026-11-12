#include "tt_engine.h"

#include <cstring>
#include <memory>
#include <new>

#include "engine/engine_core.h"
#ifdef __ANDROID__
#include "engine/device_streams.h"
#endif

namespace {

struct Engine {
  Engine(int sampleRate, int channels) : core(sampleRate, channels) {}
  tt::EngineCore core;
#ifdef __ANDROID__
  std::unique_ptr<tt::DeviceStreams> streams;
#endif
};

Engine* from(void* engine) { return static_cast<Engine*>(engine); }

}

extern "C" {

void* tt_engine_create(int sample_rate, int playback_channels) {
  if (sample_rate <= 0 || playback_channels < 1 || playback_channels > 2) return nullptr;
  auto* engine = new (std::nothrow) Engine(sample_rate, playback_channels);
#ifdef __ANDROID__
  if (engine != nullptr) engine->streams = std::make_unique<tt::DeviceStreams>(engine->core);
#endif
  return engine;
}

void tt_engine_destroy(void* engine) {
  delete from(engine);
}

int tt_engine_start_playback(void* engine) {
  if (engine == nullptr) return TT_ENGINE_NO_DEVICE;
#ifdef __ANDROID__
  return from(engine)->streams->startPlayback();
#else
  return TT_ENGINE_NO_DEVICE;
#endif
}

void tt_engine_start_playback_async(void* engine) {
  if (engine == nullptr) return;
#ifdef __ANDROID__
  from(engine)->streams->startPlaybackAsync();
#endif
}

void tt_engine_set_output(void* engine, int mode, int device_id) {
  if (engine == nullptr) return;
#ifdef __ANDROID__
  from(engine)->streams->setOutput(mode == TT_ENGINE_MODE_VOICE_CALL, device_id);
#else
  (void)mode;
  (void)device_id;
#endif
}

void tt_engine_stop_playback(void* engine) {
  if (engine == nullptr) return;
#ifdef __ANDROID__
  from(engine)->streams->stopPlayback();
#else
  from(engine)->core.resetSpeakers();
#endif
}

int tt_engine_start_capture(void* engine, int audio_source, int sample_rate, int channels) {
  if (engine == nullptr || channels < 1 || channels > 2 || sample_rate <= 0) {
    return TT_ENGINE_NO_DEVICE;
  }
#ifdef __ANDROID__
  return from(engine)->streams->startCapture(audio_source, sample_rate, channels);
#else
  (void)audio_source;
  return TT_ENGINE_NO_DEVICE;
#endif
}

void tt_engine_stop_capture(void* engine) {
  if (engine == nullptr) return;
#ifdef __ANDROID__
  from(engine)->streams->stopCapture();
#endif
}

int tt_engine_read_capture(void* engine, int16_t* out, int max_samples) {
  if (engine == nullptr || out == nullptr || max_samples <= 0) return 0;
  return static_cast<int>(from(engine)->core.readCapture(out, static_cast<size_t>(max_samples)));
}

int tt_engine_write_speaker(void* engine, int32_t key, const int16_t* pcm, int samples,
                            float gain) {
  if (engine == nullptr || pcm == nullptr || samples <= 0) return 0;
  return from(engine)->core.writeSpeaker(key, pcm, static_cast<size_t>(samples), gain);
}

int tt_engine_speaker_queued(void* engine, int32_t key) {
  if (engine == nullptr) return 0;
  return static_cast<int>(from(engine)->core.speakerQueued(key));
}

void tt_engine_remove_speaker(void* engine, int32_t key) {
  if (engine != nullptr) from(engine)->core.removeSpeaker(key);
}

void tt_engine_set_master_gain(void* engine, float gain) {
  if (engine != nullptr) from(engine)->core.setMasterGain(gain);
}

void tt_engine_get_stats(void* engine, TtEngineStats* stats) {
  if (engine == nullptr || stats == nullptr) return;
  std::memset(stats, 0, sizeof(*stats));
  Engine* e = from(engine);
  stats->active_speakers = e->core.activeSpeakers();
  stats->speaker_dropped = e->core.speakerDropped();
  stats->capture_overflow = e->core.captureOverflow();
  stats->rendered_frames = e->core.renderedFrames();
  stats->playback_latency_ms = -1;
  stats->capture_latency_ms = -1;
#ifdef __ANDROID__
  const auto playback = e->streams->playbackInfo();
  stats->playback_running = playback.running ? 1 : 0;
  stats->playback_sample_rate = playback.sampleRate;
  stats->playback_burst_frames = playback.burstFrames;
  stats->playback_buffer_frames = playback.bufferFrames;
  stats->playback_xruns = playback.xruns;
  stats->playback_latency_ms = playback.latencyMs;
  const auto capture = e->streams->captureInfo();
  stats->capture_running = capture.running ? 1 : 0;
  stats->capture_sample_rate = capture.sampleRate;
  stats->capture_channels = capture.channels;
  stats->capture_xruns = capture.xruns;
  stats->capture_latency_ms = capture.latencyMs;
  stats->last_error = e->streams->lastError();
#endif
}

void tt_engine_render(void* engine, int16_t* out, int frames) {
  if (engine == nullptr || out == nullptr || frames <= 0) return;
  from(engine)->core.render(out, static_cast<size_t>(frames));
}

void tt_engine_push_capture(void* engine, const int16_t* in, int samples) {
  if (engine == nullptr || in == nullptr || samples <= 0) return;
  from(engine)->core.pushCapture(in, static_cast<size_t>(samples));
}

}
