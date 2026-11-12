#ifndef TT_STRETCH_WRAPPER_H
#define TT_STRETCH_WRAPPER_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

TT_EXPORT void* tt_stretch_create(int sample_rate, int channels);

TT_EXPORT int tt_stretch_process(void* stretch, const int16_t* in, int frames, float speed,
                                 int16_t* out, int max_frames);

TT_EXPORT int tt_stretch_flush(void* stretch, int16_t* out, int max_frames);

TT_EXPORT void tt_stretch_destroy(void* stretch);

#ifdef __cplusplus
}
#endif

#endif
