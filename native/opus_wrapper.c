#include "opus_wrapper.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include <opus.h>

typedef struct {
  OpusDecoder* decoder;
  OpusDREDDecoder* dred_decoder;
  OpusDRED* dred;
  int sample_rate;
  uint8_t parsed[1500];
  int parsed_length;
  int parsed_needed;
  int dred_available;
} TtOpusDecoder;

void* tt_opus_encoder_create(int sample_rate, int channels, int application, int bitrate) {
  int error = OPUS_OK;
  OpusEncoder* encoder = opus_encoder_create(sample_rate, channels, application, &error);
  if (error != OPUS_OK || encoder == NULL) {
    if (encoder != NULL) opus_encoder_destroy(encoder);
    return NULL;
  }
  if (bitrate > 0) {
    opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
  }
  return encoder;
}

int tt_opus_encoder_configure(void* encoder, int complexity, int fec, int dtx, int vbr, int vbr_constraint) {
  if (encoder == NULL) return OPUS_INVALID_STATE;
  OpusEncoder* enc = (OpusEncoder*)encoder;
  int err = OPUS_OK;
  err = opus_encoder_ctl(enc, OPUS_SET_COMPLEXITY(complexity));
  if (err != OPUS_OK) return err;
  err = opus_encoder_ctl(enc, OPUS_SET_INBAND_FEC(fec ? 1 : 0));
  if (err != OPUS_OK) return err;
  err = opus_encoder_ctl(enc, OPUS_SET_DTX(dtx ? 1 : 0));
  if (err != OPUS_OK) return err;
  err = opus_encoder_ctl(enc, OPUS_SET_VBR(vbr ? 1 : 0));
  if (err != OPUS_OK) return err;
  err = opus_encoder_ctl(enc, OPUS_SET_VBR_CONSTRAINT(vbr_constraint ? 1 : 0));
  return err;
}

int tt_opus_encoder_set_loss(void* encoder, int loss_percent, int dred_ms) {
  if (encoder == NULL) return OPUS_INVALID_STATE;
  OpusEncoder* enc = (OpusEncoder*)encoder;
  int err = opus_encoder_ctl(enc, OPUS_SET_PACKET_LOSS_PERC(loss_percent));
  if (err != OPUS_OK) return err;
  return opus_encoder_ctl(enc, OPUS_SET_DRED_DURATION(dred_ms / 10));
}

int tt_opus_encode(void* encoder, const int16_t* pcm, int samples_per_channel, uint8_t* output, int max_bytes) {
  if (encoder == NULL) return OPUS_INVALID_STATE;
  return opus_encode((OpusEncoder*)encoder, pcm, samples_per_channel, output, max_bytes);
}

void tt_opus_encoder_destroy(void* encoder) {
  if (encoder != NULL) opus_encoder_destroy((OpusEncoder*)encoder);
}

void tt_opus_decoder_destroy(void* decoder) {
  TtOpusDecoder* d = (TtOpusDecoder*)decoder;
  if (d == NULL) return;
  if (d->decoder != NULL) opus_decoder_destroy(d->decoder);
  if (d->dred_decoder != NULL) opus_dred_decoder_destroy(d->dred_decoder);
  if (d->dred != NULL) opus_dred_free(d->dred);
  free(d);
}

void* tt_opus_decoder_create(int sample_rate, int channels) {
  TtOpusDecoder* d = (TtOpusDecoder*)calloc(1, sizeof(TtOpusDecoder));
  if (d == NULL) return NULL;
  int error = OPUS_OK;
  d->sample_rate = sample_rate;
  d->decoder = opus_decoder_create(sample_rate, channels, &error);
  if (error != OPUS_OK || d->decoder == NULL) {
    tt_opus_decoder_destroy(d);
    return NULL;
  }
  d->dred_decoder = opus_dred_decoder_create(&error);
  if (error != OPUS_OK) d->dred_decoder = NULL;
  d->dred = opus_dred_alloc(&error);
  if (error != OPUS_OK) d->dred = NULL;
  return d;
}

int tt_opus_decoder_set_quality(void* decoder, int complexity, int bandwidth_extension) {
  TtOpusDecoder* d = (TtOpusDecoder*)decoder;
  if (d == NULL) return OPUS_INVALID_STATE;
  int err = opus_decoder_ctl(d->decoder, OPUS_SET_COMPLEXITY(complexity));
  if (err != OPUS_OK) return err;
  return opus_decoder_ctl(d->decoder, OPUS_SET_OSCE_BWE(bandwidth_extension ? 1 : 0));
}

int tt_opus_decode(void* decoder, const uint8_t* data, int length, int16_t* pcm, int max_samples_per_channel, int decode_fec) {
  TtOpusDecoder* d = (TtOpusDecoder*)decoder;
  if (d == NULL) return OPUS_INVALID_STATE;
  return opus_decode(d->decoder, data, length, pcm, max_samples_per_channel, decode_fec);
}

int tt_opus_recover(void* decoder, const uint8_t* next, int next_length, int offset, int16_t* pcm, int frame_size, int* method) {
  TtOpusDecoder* d = (TtOpusDecoder*)decoder;
  if (d == NULL) return OPUS_INVALID_STATE;
  *method = TT_OPUS_CONCEALED;
  if (next != NULL && next_length > 0 && offset >= frame_size) {
    if (offset == frame_size && opus_packet_has_lbrr(next, next_length) == 1) {
      int ret = opus_decode(d->decoder, next, next_length, pcm, frame_size, 1);
      if (ret == frame_size) {
        *method = TT_OPUS_FEC;
        return ret;
      }
    }
    if (d->dred_decoder != NULL && d->dred != NULL) {
      int needed = offset < d->sample_rate ? offset : d->sample_rate;
      int same = next_length <= (int)sizeof(d->parsed) && next_length == d->parsed_length &&
                 needed <= d->parsed_needed && memcmp(next, d->parsed, (size_t)next_length) == 0;
      if (!same) {
        int dred_end = 0;
        int ret = opus_dred_parse(d->dred_decoder, d->dred, next, next_length, needed,
                                  d->sample_rate, &dred_end, 0);
        d->dred_available = ret > 0 ? ret : 0;
        d->parsed_length = 0;
        if (next_length <= (int)sizeof(d->parsed)) {
          memcpy(d->parsed, next, (size_t)next_length);
          d->parsed_length = next_length;
          d->parsed_needed = needed;
        }
      }
      if (d->dred_available > 0) {
        int ret = opus_decoder_dred_decode(d->decoder, d->dred, offset, pcm, frame_size);
        if (ret == frame_size) {
          *method = TT_OPUS_DRED;
          return ret;
        }
      }
    }
  }
  return opus_decode(d->decoder, NULL, 0, pcm, frame_size, 0);
}
