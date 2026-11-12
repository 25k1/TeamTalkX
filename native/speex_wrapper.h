#ifndef TT_SPEEX_WRAPPER_H
#define TT_SPEEX_WRAPPER_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

TT_EXPORT void* tt_speex_encoder_create(int band_mode, int complexity, int quality);
TT_EXPORT void* tt_speex_encoder_create_vbr(int band_mode, int complexity, float vbr_quality,
                                           int bitrate, int max_bitrate, int dtx);
TT_EXPORT int tt_speex_encode(void* encoder, const int16_t* pcm, uint8_t* output, int max_bytes);
TT_EXPORT void tt_speex_encoder_destroy(void* encoder);

TT_EXPORT void* tt_speex_decoder_create(int band_mode);
TT_EXPORT int tt_speex_decode(void* decoder, const uint8_t* data, int length, int16_t* pcm);
TT_EXPORT void tt_speex_decoder_destroy(void* decoder);

TT_EXPORT int tt_speex_frame_size(int band_mode);

#ifdef __cplusplus
}
#endif

#endif
