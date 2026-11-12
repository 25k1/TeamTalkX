#include "stretch_wrapper.h"

#include <stddef.h>

#include <sonic.h>

void* tt_stretch_create(int sample_rate, int channels) {
  if (sample_rate <= 0 || channels < 1 || channels > 2) return NULL;
  sonicStream stream = sonicCreateStream(sample_rate, channels);
  if (stream == NULL) return NULL;
  sonicSetQuality(stream, 0);
  return stream;
}

int tt_stretch_process(void* stretch, const int16_t* in, int frames, float speed, int16_t* out,
                       int max_frames) {
  sonicStream stream = (sonicStream)stretch;
  if (stream == NULL || out == NULL || max_frames <= 0) return 0;
  if (speed < 0.5f) speed = 0.5f;
  if (speed > 2.0f) speed = 2.0f;
  sonicSetSpeed(stream, speed);
  if (in != NULL && frames > 0) {
    if (!sonicWriteShortToStream(stream, (short*)in, frames)) return 0;
  }
  return sonicReadShortFromStream(stream, (short*)out, max_frames);
}

int tt_stretch_flush(void* stretch, int16_t* out, int max_frames) {
  sonicStream stream = (sonicStream)stretch;
  if (stream == NULL || out == NULL || max_frames <= 0) return 0;
  sonicFlushStream(stream);
  return sonicReadShortFromStream(stream, (short*)out, max_frames);
}

void tt_stretch_destroy(void* stretch) {
  if (stretch != NULL) sonicDestroyStream((sonicStream)stretch);
}
