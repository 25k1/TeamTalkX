#ifndef TT_SILERO_VAD_H
#define TT_SILERO_VAD_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

TT_EXPORT int tt_silero_chunk_size(void);

TT_EXPORT void* tt_silero_create(const uint8_t* weights, int length);

TT_EXPORT float tt_silero_process(void* vad, const float* chunk);

TT_EXPORT int tt_silero_feed(void* vad, const int16_t* pcm, int count, float* probs, int max_probs);

TT_EXPORT void tt_silero_state(void* vad, float* h, float* c);

TT_EXPORT void tt_silero_reset(void* vad);

TT_EXPORT void tt_silero_destroy(void* vad);

#ifdef __cplusplus
}
#endif

#endif
