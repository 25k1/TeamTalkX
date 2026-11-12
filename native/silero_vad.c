#include "silero_vad.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#if defined(TT_SILERO_SCALAR)
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#define TT_SILERO_NEON 1
#elif defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>
#define TT_SILERO_SSE 1
#endif

#define CHUNK 512
#define CONTEXT 64
#define INPUT (CONTEXT + CHUNK)
#define PADDED (INPUT + 64)
#define FFT 256
#define HOP 128
#define FRAMES 4
#define BINS 129
#define HIDDEN 128
#define GATES (4 * HIDDEN)

enum {
  W_STFT,
  W_ENC0, B_ENC0, W_ENC1, B_ENC1, W_ENC2, B_ENC2, W_ENC3, B_ENC3,
  W_LSTM, B_LSTM, W_HEAD, B_HEAD,
  W_COUNT
};

static const int kShapes[W_COUNT][4] = {
    {2, 2 * BINS, FFT, 0},
    {3, 128, BINS, 3}, {1, 128, 0, 0},
    {3, 64, 128, 3}, {1, 64, 0, 0},
    {3, 64, 64, 3}, {1, 64, 0, 0},
    {3, 128, 64, 3}, {1, 128, 0, 0},
    {2, GATES, 2 * HIDDEN, 0}, {1, GATES, 0, 0},
    {1, HIDDEN, 0, 0}, {1, 1, 0, 0},
};

static const int kEncoder[4][3] = {{BINS, 128, 1}, {128, 64, 2}, {64, 64, 2}, {64, 128, 1}};

typedef struct {
  float* w[W_COUNT];
  float* data;

  float x[PADDED];
  float context[CONTEXT];
  float pending[CHUNK];
  int pending_count;

  float stft[2 * BINS * FRAMES];
  float act_a[BINS * FRAMES];
  float act_b[BINS * FRAMES];
  float window[BINS * 3];
  float xh[2 * HIDDEN];
  float gates[GATES];
  float h[HIDDEN];
  float c[HIDDEN];
} Silero;

static float dot(const float* a, const float* b, int n) {
  int i = 0;
#if defined(TT_SILERO_NEON)
  float32x4_t s0 = vdupq_n_f32(0), s1 = vdupq_n_f32(0), s2 = vdupq_n_f32(0), s3 = vdupq_n_f32(0);
  for (; i + 16 <= n; i += 16) {
    s0 = vfmaq_f32(s0, vld1q_f32(a + i), vld1q_f32(b + i));
    s1 = vfmaq_f32(s1, vld1q_f32(a + i + 4), vld1q_f32(b + i + 4));
    s2 = vfmaq_f32(s2, vld1q_f32(a + i + 8), vld1q_f32(b + i + 8));
    s3 = vfmaq_f32(s3, vld1q_f32(a + i + 12), vld1q_f32(b + i + 12));
  }
  for (; i + 4 <= n; i += 4) s0 = vfmaq_f32(s0, vld1q_f32(a + i), vld1q_f32(b + i));
  float sum = vaddvq_f32(vaddq_f32(vaddq_f32(s0, s1), vaddq_f32(s2, s3)));
#elif defined(TT_SILERO_SSE)
  __m128 s0 = _mm_setzero_ps(), s1 = _mm_setzero_ps(), s2 = _mm_setzero_ps(), s3 = _mm_setzero_ps();
  for (; i + 16 <= n; i += 16) {
    s0 = _mm_add_ps(s0, _mm_mul_ps(_mm_loadu_ps(a + i), _mm_loadu_ps(b + i)));
    s1 = _mm_add_ps(s1, _mm_mul_ps(_mm_loadu_ps(a + i + 4), _mm_loadu_ps(b + i + 4)));
    s2 = _mm_add_ps(s2, _mm_mul_ps(_mm_loadu_ps(a + i + 8), _mm_loadu_ps(b + i + 8)));
    s3 = _mm_add_ps(s3, _mm_mul_ps(_mm_loadu_ps(a + i + 12), _mm_loadu_ps(b + i + 12)));
  }
  for (; i + 4 <= n; i += 4) s0 = _mm_add_ps(s0, _mm_mul_ps(_mm_loadu_ps(a + i), _mm_loadu_ps(b + i)));
  float lanes[4];
  _mm_storeu_ps(lanes, _mm_add_ps(_mm_add_ps(s0, s1), _mm_add_ps(s2, s3)));
  float sum = (lanes[0] + lanes[1]) + (lanes[2] + lanes[3]);
#else
  float s[4] = {0, 0, 0, 0};
  for (; i + 4 <= n; i += 4) {
    s[0] += a[i] * b[i];
    s[1] += a[i + 1] * b[i + 1];
    s[2] += a[i + 2] * b[i + 2];
    s[3] += a[i + 3] * b[i + 3];
  }
  float sum = (s[0] + s[1]) + (s[2] + s[3]);
#endif
  for (; i < n; i++) sum += a[i] * b[i];
  return sum;
}

static float sigmoid(float v) { return 1.0f / (1.0f + expf(-v)); }

static uint32_t read_u32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int load_weights(Silero* s, const uint8_t* bytes, int length) {
  if (bytes == NULL || length < 12 || memcmp(bytes, "TTSV", 4) != 0) return 0;
  if (read_u32(bytes + 4) != 1 || read_u32(bytes + 8) != W_COUNT) return 0;

  size_t total = 0;
  for (int t = 0; t < W_COUNT; t++) {
    size_t n = 1;
    for (int d = 0; d < kShapes[t][0]; d++) n *= (size_t)kShapes[t][1 + d];
    total += n;
  }
  s->data = (float*)malloc(total * sizeof(float));
  if (s->data == NULL) return 0;

  size_t at = 12;
  float* out = s->data;
  for (int t = 0; t < W_COUNT; t++) {
    const int ndim = kShapes[t][0];
    if (at + 4 + 4 * (size_t)ndim > (size_t)length || read_u32(bytes + at) != (uint32_t)ndim) return 0;
    at += 4;
    size_t n = 1;
    for (int d = 0; d < ndim; d++) {
      if (read_u32(bytes + at) != (uint32_t)kShapes[t][1 + d]) return 0;
      n *= (size_t)kShapes[t][1 + d];
      at += 4;
    }
    if (at + n * 4 > (size_t)length) return 0;
    memcpy(out, bytes + at, n * 4);
    s->w[t] = out;
    out += n;
    at += n * 4;
  }
  return at == (size_t)length;
}

int tt_silero_chunk_size(void) { return CHUNK; }

void* tt_silero_create(const uint8_t* weights, int length) {
  Silero* s = (Silero*)calloc(1, sizeof(Silero));
  if (s == NULL) return NULL;
  if (!load_weights(s, weights, length)) {
    free(s->data);
    free(s);
    return NULL;
  }
  return s;
}

static void conv_relu(Silero* s, const float* in, int cin, int tin, const float* w, const float* b, int cout,
                      int stride, float* out, int* tout) {
  const int steps = (tin - 1) / stride + 1;
  const int width = cin * 3;
  for (int t = 0; t < steps; t++) {
    for (int ch = 0; ch < cin; ch++) {
      for (int k = 0; k < 3; k++) {
        const int at = t * stride + k - 1;
        s->window[ch * 3 + k] = (at >= 0 && at < tin) ? in[ch * tin + at] : 0.0f;
      }
    }
    for (int o = 0; o < cout; o++) {
      const float v = b[o] + dot(w + (size_t)o * width, s->window, width);
      out[o * steps + t] = v > 0 ? v : 0;
    }
  }
  *tout = steps;
}

float tt_silero_process(void* vad, const float* chunk) {
  Silero* s = (Silero*)vad;
  if (s == NULL || chunk == NULL) return 0.0f;

  memcpy(s->x, s->context, sizeof(s->context));
  memcpy(s->x + CONTEXT, chunk, CHUNK * sizeof(float));
  memcpy(s->context, chunk + CHUNK - CONTEXT, sizeof(s->context));
  for (int j = 0; j < PADDED - INPUT; j++) s->x[INPUT + j] = s->x[INPUT - 2 - j];

  const float* basis = s->w[W_STFT];
  for (int f = 0; f < FRAMES; f++) {
    const float* frame = s->x + f * HOP;
    for (int r = 0; r < 2 * BINS; r++) s->stft[r * FRAMES + f] = dot(basis + (size_t)r * FFT, frame, FFT);
  }
  for (int bin = 0; bin < BINS; bin++) {
    for (int f = 0; f < FRAMES; f++) {
      const float re = s->stft[bin * FRAMES + f];
      const float im = s->stft[(BINS + bin) * FRAMES + f];
      s->act_a[bin * FRAMES + f] = sqrtf(re * re + im * im);
    }
  }

  float* in = s->act_a;
  float* out = s->act_b;
  int t = FRAMES;
  for (int layer = 0; layer < 4; layer++) {
    conv_relu(s, in, kEncoder[layer][0], t, s->w[W_ENC0 + 2 * layer], s->w[B_ENC0 + 2 * layer],
              kEncoder[layer][1], kEncoder[layer][2], out, &t);
    float* swap = in;
    in = out;
    out = swap;
  }

  memcpy(s->xh, in, HIDDEN * sizeof(float));
  memcpy(s->xh + HIDDEN, s->h, HIDDEN * sizeof(float));
  const float* lw = s->w[W_LSTM];
  const float* lb = s->w[B_LSTM];
  for (int r = 0; r < GATES; r++) s->gates[r] = lb[r] + dot(lw + (size_t)r * 2 * HIDDEN, s->xh, 2 * HIDDEN);
  for (int j = 0; j < HIDDEN; j++) {
    const float gi = sigmoid(s->gates[j]);
    const float gf = sigmoid(s->gates[HIDDEN + j]);
    const float gg = tanhf(s->gates[2 * HIDDEN + j]);
    const float go = sigmoid(s->gates[3 * HIDDEN + j]);
    s->c[j] = gf * s->c[j] + gi * gg;
    s->h[j] = go * tanhf(s->c[j]);
  }

  const float* hw = s->w[W_HEAD];
  float logit = s->w[B_HEAD][0];
  for (int j = 0; j < HIDDEN; j++) logit += hw[j] * (s->h[j] > 0 ? s->h[j] : 0);
  return sigmoid(logit);
}

int tt_silero_feed(void* vad, const int16_t* pcm, int count, float* probs, int max_probs) {
  Silero* s = (Silero*)vad;
  if (s == NULL || pcm == NULL || count <= 0) return 0;
  int chunks = 0;
  for (int i = 0; i < count; i++) {
    s->pending[s->pending_count++] = pcm[i] / 32768.0f;
    if (s->pending_count == CHUNK) {
      const float p = tt_silero_process(s, s->pending);
      if (probs != NULL && chunks < max_probs) probs[chunks] = p;
      chunks++;
      s->pending_count = 0;
    }
  }
  return chunks;
}

void tt_silero_state(void* vad, float* h, float* c) {
  Silero* s = (Silero*)vad;
  if (s == NULL) return;
  if (h != NULL) memcpy(h, s->h, sizeof(s->h));
  if (c != NULL) memcpy(c, s->c, sizeof(s->c));
}

void tt_silero_reset(void* vad) {
  Silero* s = (Silero*)vad;
  if (s == NULL) return;
  memset(s->context, 0, sizeof(s->context));
  memset(s->h, 0, sizeof(s->h));
  memset(s->c, 0, sizeof(s->c));
  s->pending_count = 0;
}

void tt_silero_destroy(void* vad) {
  Silero* s = (Silero*)vad;
  if (s == NULL) return;
  free(s->data);
  free(s);
}
