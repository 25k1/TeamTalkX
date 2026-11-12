#ifndef TT_RNNOISE_WRAPPER_H
#define TT_RNNOISE_WRAPPER_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

TT_EXPORT int tt_rnnoise_frame_size(void);

TT_EXPORT void* tt_rnnoise_create(void);

TT_EXPORT float tt_rnnoise_process(void* denoiser, const int16_t* in, int16_t* out, float wet);

TT_EXPORT void tt_rnnoise_reset(void* denoiser);

TT_EXPORT void tt_rnnoise_destroy(void* denoiser);

#ifdef __cplusplus
}
#endif

#endif
