#include "media_decoder.h"

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>

#define PCM_16BIT 2
#define PCM_FLOAT 4

#define TIMEOUT_US 5000
#define MAX_TRIES 400

typedef struct {
  int fd;
  AMediaExtractor* extractor;
  AMediaCodec* codec;
  int sample_rate;
  int channels;
  int encoding;
  int out_rate;
  int out_channels;
  int64_t duration_us;
  int input_done;
  int output_done;
  int64_t seek_target_us;
  int16_t* pending;
  int pending_rate;
  int pending_channels;
  int pending_len;
  int pending_pos;
  int pending_cap;
} tt_media;

static void update_format(tt_media* m, AMediaFormat* format) {
  int32_t v = 0;
  if (AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &v) && v > 0) m->sample_rate = v;
  if (AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &v) && v > 0) m->channels = v;
  if (AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_PCM_ENCODING, &v)) m->encoding = v;
}

void tt_media_close(void* media) {
  tt_media* m = (tt_media*)media;
  if (m == NULL) return;
  if (m->codec != NULL) {
    AMediaCodec_stop(m->codec);
    AMediaCodec_delete(m->codec);
  }
  if (m->extractor != NULL) AMediaExtractor_delete(m->extractor);
  if (m->fd >= 0) close(m->fd);
  free(m->pending);
  free(m);
}

void* tt_media_open(const char* path) {
  if (path == NULL) return NULL;
  tt_media* m = (tt_media*)calloc(1, sizeof(tt_media));
  if (m == NULL) return NULL;
  m->fd = open(path, O_RDONLY);
  m->encoding = PCM_16BIT;
  m->duration_us = -1;
  m->seek_target_us = -1;
  struct stat st;
  if (m->fd < 0 || fstat(m->fd, &st) != 0) goto fail;
  m->extractor = AMediaExtractor_new();
  if (m->extractor == NULL ||
      AMediaExtractor_setDataSourceFd(m->extractor, m->fd, 0, st.st_size) != AMEDIA_OK) {
    goto fail;
  }
  size_t tracks = AMediaExtractor_getTrackCount(m->extractor);
  for (size_t i = 0; i < tracks && m->codec == NULL; i++) {
    AMediaFormat* format = AMediaExtractor_getTrackFormat(m->extractor, i);
    const char* mime = NULL;
    if (AMediaFormat_getString(format, AMEDIAFORMAT_KEY_MIME, &mime) && mime != NULL &&
        strncmp(mime, "audio/", 6) == 0) {
      update_format(m, format);
      int64_t duration = 0;
      if (AMediaFormat_getInt64(format, AMEDIAFORMAT_KEY_DURATION, &duration)) m->duration_us = duration;
      AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_PCM_ENCODING, PCM_16BIT);
      AMediaCodec* codec = AMediaCodec_createDecoderByType(mime);
      if (codec != NULL && AMediaCodec_configure(codec, format, NULL, NULL, 0) == AMEDIA_OK &&
          AMediaCodec_start(codec) == AMEDIA_OK) {
        AMediaExtractor_selectTrack(m->extractor, i);
        m->codec = codec;
      } else if (codec != NULL) {
        AMediaCodec_delete(codec);
      }
    }
    AMediaFormat_delete(format);
  }
  if (m->codec == NULL || m->sample_rate <= 0 || m->channels <= 0) goto fail;
  m->encoding = PCM_16BIT;
  m->out_rate = m->sample_rate;
  m->out_channels = m->channels;
  return m;
fail:
  tt_media_close(m);
  return NULL;
}

int tt_media_sample_rate(void* media) { return media ? ((tt_media*)media)->out_rate : 0; }
int tt_media_channels(void* media) { return media ? ((tt_media*)media)->out_channels : 0; }
int64_t tt_media_duration_us(void* media) { return media ? ((tt_media*)media)->duration_us : -1; }

static int ensure_pending(tt_media* m, int samples) {
  if (m->pending_cap >= samples) return 1;
  int16_t* grown = (int16_t*)realloc(m->pending, (size_t)samples * sizeof(int16_t));
  if (grown == NULL) return 0;
  m->pending = grown;
  m->pending_cap = samples;
  return 1;
}

static void feed_input(tt_media* m) {
  if (m->input_done) return;
  ssize_t index = AMediaCodec_dequeueInputBuffer(m->codec, 0);
  if (index < 0) return;
  size_t size = 0;
  uint8_t* buffer = AMediaCodec_getInputBuffer(m->codec, (size_t)index, &size);
  ssize_t n = buffer ? AMediaExtractor_readSampleData(m->extractor, buffer, size) : -1;
  if (n < 0) {
    AMediaCodec_queueInputBuffer(m->codec, (size_t)index, 0, 0, 0,
                                 AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
    m->input_done = 1;
    return;
  }
  int64_t pts = AMediaExtractor_getSampleTime(m->extractor);
  AMediaCodec_queueInputBuffer(m->codec, (size_t)index, 0, (size_t)n, (uint64_t)(pts < 0 ? 0 : pts), 0);
  AMediaExtractor_advance(m->extractor);
}

static int drain_output(tt_media* m) {
  AMediaCodecBufferInfo info;
  ssize_t index = AMediaCodec_dequeueOutputBuffer(m->codec, &info, TIMEOUT_US);
  if (index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
    AMediaFormat* format = AMediaCodec_getOutputFormat(m->codec);
    if (format != NULL) {
      update_format(m, format);
      AMediaFormat_delete(format);
    }
    return 0;
  }
  if (index < 0) return 0;
  size_t size = 0;
  uint8_t* buffer = AMediaCodec_getOutputBuffer(m->codec, (size_t)index, &size);
  int ok = 1;
  if (buffer != NULL && info.size > 0) {
    const uint8_t* data = buffer + info.offset;
    int samples = m->encoding == PCM_FLOAT ? info.size / 4 : info.size / 2;
    if (ensure_pending(m, samples)) {
      if (m->encoding == PCM_FLOAT) {
        const float* f = (const float*)data;
        for (int i = 0; i < samples; i++) {
          float v = f[i] * 32767.0f;
          m->pending[i] = (int16_t)(v > 32767.0f ? 32767 : (v < -32768.0f ? -32768 : v));
        }
      } else {
        memcpy(m->pending, data, (size_t)samples * 2);
      }
      m->pending_len = samples;
      m->pending_pos = 0;
      m->pending_rate = m->sample_rate;
      m->pending_channels = m->channels;
      if (m->seek_target_us >= 0 && m->sample_rate > 0 && m->channels > 0) {
        int64_t skip_us = m->seek_target_us - info.presentationTimeUs;
        int64_t skip = skip_us > 0 ? skip_us * m->sample_rate / 1000000 * m->channels : 0;
        if (skip >= samples) {
          m->pending_len = 0;
        } else {
          m->pending_pos = (int)skip;
          m->seek_target_us = -1;
        }
      }
    } else {
      ok = 0;
    }
  }
  if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) m->output_done = 1;
  AMediaCodec_releaseOutputBuffer(m->codec, (size_t)index, false);
  return ok ? 0 : -1;
}

int tt_media_read(void* media, int16_t* out, int max_samples) {
  tt_media* m = (tt_media*)media;
  if (m == NULL || out == NULL || max_samples <= 0) return -1;
  int written = 0;
  int wanted = max_samples;
  int tries = 0;
  while (written < wanted) {
    if (m->pending_pos < m->pending_len) {
      if (m->pending_rate != m->out_rate || m->pending_channels != m->out_channels) {
        if (written > 0) break;
        m->out_rate = m->pending_rate;
        m->out_channels = m->pending_channels;
      }
      if (written == 0) {
        int channels = m->out_channels > 0 ? m->out_channels : 1;
        wanted = max_samples - max_samples % channels;
      }
      int n = m->pending_len - m->pending_pos;
      if (n > wanted - written) n = wanted - written;
      memcpy(out + written, m->pending + m->pending_pos, (size_t)n * 2);
      m->pending_pos += n;
      written += n;
      continue;
    }
    if (m->output_done) break;
    if (written > 0 && tries > 0) break;
    if (++tries > MAX_TRIES) break;
    feed_input(m);
    if (drain_output(m) < 0) return -1;
  }
  return written;
}

int tt_media_seek(void* media, int64_t position_us) {
  tt_media* m = (tt_media*)media;
  if (m == NULL) return -1;
  if (position_us < 0) position_us = 0;
  if (AMediaExtractor_seekTo(m->extractor, position_us, AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC) != AMEDIA_OK) {
    return -1;
  }
  AMediaCodec_flush(m->codec);
  m->pending_len = 0;
  m->pending_pos = 0;
  m->input_done = 0;
  m->output_done = 0;
  m->seek_target_us = position_us;
  return 0;
}
