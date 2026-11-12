#include "speex_wrapper.h"

#include <stdlib.h>

#include <speex/speex.h>

typedef struct {
  void* state;
  SpeexBits bits;
  int frame_size;
} tt_speex;

static const SpeexMode* mode_for(int band_mode) {
  switch (band_mode) {
    case 0: return &speex_nb_mode;
    case 1: return &speex_wb_mode;
    case 2: return &speex_uwb_mode;
    default: return NULL;
  }
}

int tt_speex_frame_size(int band_mode) {
  const SpeexMode* mode = mode_for(band_mode);
  int size = -1;
  if (mode == NULL || speex_mode_query(mode, SPEEX_MODE_FRAME_SIZE, &size) != 0) return -1;
  return size;
}

static tt_speex* encoder_common(int band_mode, int complexity) {
  const SpeexMode* mode = mode_for(band_mode);
  if (mode == NULL) return NULL;
  tt_speex* s = (tt_speex*)calloc(1, sizeof(tt_speex));
  if (s == NULL) return NULL;
  s->state = speex_encoder_init(mode);
  if (s->state == NULL) {
    free(s);
    return NULL;
  }
  speex_bits_init(&s->bits);
  speex_encoder_ctl(s->state, SPEEX_GET_FRAME_SIZE, &s->frame_size);
  speex_encoder_ctl(s->state, SPEEX_SET_COMPLEXITY, &complexity);
  return s;
}

void* tt_speex_encoder_create(int band_mode, int complexity, int quality) {
  tt_speex* s = encoder_common(band_mode, complexity);
  if (s == NULL) return NULL;
  if (speex_encoder_ctl(s->state, SPEEX_SET_QUALITY, &quality) != 0) {
    tt_speex_encoder_destroy(s);
    return NULL;
  }
  return s;
}

void* tt_speex_encoder_create_vbr(int band_mode, int complexity, float vbr_quality,
                                  int bitrate, int max_bitrate, int dtx) {
  tt_speex* s = encoder_common(band_mode, complexity);
  if (s == NULL) return NULL;
  int on = 1;
  int ok = 1;
  if (max_bitrate != 0) ok &= speex_encoder_ctl(s->state, SPEEX_SET_VBR_MAX_BITRATE, &max_bitrate) == 0;
  if (bitrate != 0) {
    ok &= speex_encoder_ctl(s->state, SPEEX_SET_BITRATE, &bitrate) == 0;
  } else {
    ok &= speex_encoder_ctl(s->state, SPEEX_SET_VBR_QUALITY, &vbr_quality) == 0;
  }
  if (dtx) ok &= speex_encoder_ctl(s->state, SPEEX_SET_DTX, &on) == 0;
  ok &= speex_encoder_ctl(s->state, SPEEX_SET_VBR, &on) == 0;
  if (!ok) {
    tt_speex_encoder_destroy(s);
    return NULL;
  }
  return s;
}

int tt_speex_encode(void* encoder, const int16_t* pcm, uint8_t* output, int max_bytes) {
  tt_speex* s = (tt_speex*)encoder;
  if (s == NULL || pcm == NULL || output == NULL) return -1;
  speex_bits_reset(&s->bits);
  speex_encode_int(s->state, (spx_int16_t*)pcm, &s->bits);
  return speex_bits_write(&s->bits, (char*)output, max_bytes);
}

void tt_speex_encoder_destroy(void* encoder) {
  tt_speex* s = (tt_speex*)encoder;
  if (s == NULL) return;
  speex_bits_destroy(&s->bits);
  speex_encoder_destroy(s->state);
  free(s);
}

void* tt_speex_decoder_create(int band_mode) {
  const SpeexMode* mode = mode_for(band_mode);
  if (mode == NULL) return NULL;
  tt_speex* s = (tt_speex*)calloc(1, sizeof(tt_speex));
  if (s == NULL) return NULL;
  s->state = speex_decoder_init(mode);
  if (s->state == NULL) {
    free(s);
    return NULL;
  }
  speex_bits_init(&s->bits);
  speex_decoder_ctl(s->state, SPEEX_GET_FRAME_SIZE, &s->frame_size);
  return s;
}

int tt_speex_decode(void* decoder, const uint8_t* data, int length, int16_t* pcm) {
  tt_speex* s = (tt_speex*)decoder;
  if (s == NULL || pcm == NULL) return -1;
  int result;
  if (data != NULL && length > 0) {
    speex_bits_read_from(&s->bits, (const char*)data, length);
    result = speex_decode_int(s->state, &s->bits, (spx_int16_t*)pcm);
  } else {
    result = speex_decode_int(s->state, NULL, (spx_int16_t*)pcm);
  }
  return result == 0 ? s->frame_size : -1;
}

void tt_speex_decoder_destroy(void* decoder) {
  tt_speex* s = (tt_speex*)decoder;
  if (s == NULL) return;
  speex_bits_destroy(&s->bits);
  speex_decoder_destroy(s->state);
  free(s);
}
