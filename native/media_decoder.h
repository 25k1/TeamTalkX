#ifndef TT_MEDIA_DECODER_H
#define TT_MEDIA_DECODER_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

TT_EXPORT void* tt_media_open(const char* path);

TT_EXPORT int tt_media_sample_rate(void* media);
TT_EXPORT int tt_media_channels(void* media);

TT_EXPORT int64_t tt_media_duration_us(void* media);

TT_EXPORT int tt_media_read(void* media, int16_t* out, int max_samples);

TT_EXPORT int tt_media_seek(void* media, int64_t position_us);

TT_EXPORT void tt_media_close(void* media);

#ifdef __cplusplus
}
#endif

#endif
