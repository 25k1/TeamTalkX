#include "rnnoise_wrapper.h"

#include <stdlib.h>
#include <string.h>

#include <rnnoise.h>

#define FRAME 480

typedef struct {
  DenoiseState* state;
  float dry[FRAME];
  int frames;
} TtRnnoise;

int tt_rnnoise_frame_size(void) { return FRAME; }

void* tt_rnnoise_create(void) {
  if (rnnoise_get_frame_size() != FRAME) return NULL;
  TtRnnoise* d = (TtRnnoise*)calloc(1, sizeof(TtRnnoise));
  if (d == NULL) return NULL;
  d->state = rnnoise_create(NULL);
  if (d->state == NULL) {
    free(d);
    return NULL;
  }
  return d;
}

static int16_t clamp16(float v) {
  if (v > 32767.0f) return 32767;
  if (v < -32768.0f) return -32768;
  return (int16_t)(v >= 0 ? v + 0.5f : v - 0.5f);
}

float tt_rnnoise_process(void* denoiser, const int16_t* in, int16_t* out, float wet) {
  TtRnnoise* d = (TtRnnoise*)denoiser;
  if (d == NULL || in == NULL || out == NULL) return 0.0f;
  if (wet < 0.0f) wet = 0.0f;
  if (wet > 1.0f) wet = 1.0f;

  float input[FRAME];
  float denoised[FRAME];
  for (int i = 0; i < FRAME; i++) input[i] = (float)in[i];
  const float vad = rnnoise_process_frame(d->state, denoised, input);

  if (d->frames == 0) {
    memset(out, 0, FRAME * sizeof(int16_t));
  } else {
    for (int i = 0; i < FRAME; i++) {
      out[i] = clamp16(wet * denoised[i] + (1.0f - wet) * d->dry[i]);
    }
  }
  memcpy(d->dry, input, sizeof(input));
  d->frames++;
  return vad;
}

void tt_rnnoise_reset(void* denoiser) {
  TtRnnoise* d = (TtRnnoise*)denoiser;
  if (d == NULL) return;
  rnnoise_init(d->state, NULL);
  memset(d->dry, 0, sizeof(d->dry));
  d->frames = 0;
}

void tt_rnnoise_destroy(void* denoiser) {
  TtRnnoise* d = (TtRnnoise*)denoiser;
  if (d == NULL) return;
  rnnoise_destroy(d->state);
  free(d);
}
