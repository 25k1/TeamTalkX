#ifndef TT_OPUS_WRAPPER_H
#define TT_OPUS_WRAPPER_H

#include <stdint.h>

#include "tt_export.h"

#ifdef __cplusplus
extern "C" {
#endif

TT_EXPORT void* tt_opus_encoder_create(int sample_rate, int channels, int application, int bitrate);
TT_EXPORT int tt_opus_encoder_configure(void* encoder, int complexity, int fec, int dtx, int vbr, int vbr_constraint);
TT_EXPORT int tt_opus_encode(void* encoder, const int16_t* pcm, int samples_per_channel, uint8_t* output, int max_bytes);
TT_EXPORT void tt_opus_encoder_destroy(void* encoder);

TT_EXPORT int tt_opus_encoder_set_loss(void* encoder, int loss_percent, int dred_ms);

enum { TT_OPUS_CONCEALED = 0, TT_OPUS_FEC = 1, TT_OPUS_DRED = 2 };

TT_EXPORT void* tt_opus_decoder_create(int sample_rate, int channels);
TT_EXPORT int tt_opus_decoder_set_quality(void* decoder, int complexity, int bandwidth_extension);
TT_EXPORT int tt_opus_decode(void* decoder, const uint8_t* data, int length, int16_t* pcm, int max_samples_per_channel, int decode_fec);
TT_EXPORT int tt_opus_recover(void* decoder, const uint8_t* next, int next_length, int offset, int16_t* pcm, int frame_size, int* method);
TT_EXPORT void tt_opus_decoder_destroy(void* decoder);

#ifdef __cplusplus
}
#endif

#endif
