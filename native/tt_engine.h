#ifndef TT_ENGINE_H
#define TT_ENGINE_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TT_ENGINE_NO_DEVICE (-1000)

typedef struct TtEngineStats {
  int64_t playback_running;
  int64_t playback_sample_rate;
  int64_t playback_burst_frames;
  int64_t playback_buffer_frames;
  int64_t playback_xruns;
  int64_t capture_running;
  int64_t capture_sample_rate;
  int64_t capture_channels;
  int64_t capture_xruns;
  int64_t active_speakers;
  int64_t speaker_dropped;
  int64_t capture_overflow;
  int64_t rendered_frames;
  int64_t last_error;
  double playback_latency_ms;
  double capture_latency_ms;
} TtEngineStats;

TT_EXPORT void* tt_engine_create(int sample_rate, int playback_channels);
TT_EXPORT void tt_engine_destroy(void* engine);

TT_EXPORT int tt_engine_start_playback(void* engine);
TT_EXPORT void tt_engine_start_playback_async(void* engine);
TT_EXPORT void tt_engine_stop_playback(void* engine);

TT_EXPORT int tt_engine_start_capture(void* engine, int audio_source, int sample_rate,
                                      int channels);
TT_EXPORT void tt_engine_stop_capture(void* engine);

TT_EXPORT int tt_engine_read_capture(void* engine, int16_t* out, int max_samples);

TT_EXPORT int tt_engine_write_speaker(void* engine, int32_t key, const int16_t* pcm,
                                      int samples, float gain);
TT_EXPORT void tt_engine_remove_speaker(void* engine, int32_t key);

TT_EXPORT int tt_engine_speaker_queued(void* engine, int32_t key);
TT_EXPORT void tt_engine_set_master_gain(void* engine, float gain);

#define TT_ENGINE_MODE_MEDIA 0
#define TT_ENGINE_MODE_VOICE_CALL 1
TT_EXPORT void tt_engine_set_output(void* engine, int mode, int device_id);

TT_EXPORT void tt_engine_get_stats(void* engine, TtEngineStats* stats);

TT_EXPORT void tt_engine_render(void* engine, int16_t* out, int frames);
TT_EXPORT void tt_engine_push_capture(void* engine, const int16_t* in, int samples);

#ifdef __cplusplus
}
#endif

#endif
