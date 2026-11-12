#ifndef TT_ENGINE_RING_H
#define TT_ENGINE_RING_H

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

namespace tt {

class Ring {
 public:
  explicit Ring(size_t capacity) : buffer_(roundUp(capacity)), mask_(buffer_.size() - 1) {}

  size_t capacity() const { return buffer_.size(); }

  size_t available() const {
    return static_cast<size_t>(write_.load(std::memory_order_acquire) -
                               read_.load(std::memory_order_acquire));
  }

  size_t write(const int16_t* in, size_t count) {
    const uint64_t w = write_.load(std::memory_order_relaxed);
    const uint64_t r = read_.load(std::memory_order_acquire);
    const size_t free = buffer_.size() - static_cast<size_t>(w - r);
    const size_t n = count < free ? count : free;
    copyIn(w, in, n);
    write_.store(w + n, std::memory_order_release);
    return n;
  }

  size_t read(int16_t* out, size_t count) {
    const uint64_t r = read_.load(std::memory_order_relaxed);
    const uint64_t w = write_.load(std::memory_order_acquire);
    const size_t ready = static_cast<size_t>(w - r);
    const size_t n = count < ready ? count : ready;
    copyOut(r, out, n);
    read_.store(r + n, std::memory_order_release);
    return n;
  }

  size_t trim(size_t keep) {
    const uint64_t r = read_.load(std::memory_order_relaxed);
    const uint64_t w = write_.load(std::memory_order_acquire);
    const size_t ready = static_cast<size_t>(w - r);
    if (ready <= keep) return 0;
    const size_t drop = ready - keep;
    read_.store(r + drop, std::memory_order_release);
    return drop;
  }

  void clear() { read_.store(write_.load(std::memory_order_acquire), std::memory_order_release); }

 private:
  static size_t roundUp(size_t n) {
    size_t size = 1;
    while (size < n) size <<= 1;
    return size;
  }

  void copyIn(uint64_t at, const int16_t* in, size_t n) {
    const size_t start = static_cast<size_t>(at) & mask_;
    const size_t first = n < buffer_.size() - start ? n : buffer_.size() - start;
    std::memcpy(&buffer_[start], in, first * sizeof(int16_t));
    std::memcpy(&buffer_[0], in + first, (n - first) * sizeof(int16_t));
  }

  void copyOut(uint64_t at, int16_t* out, size_t n) const {
    const size_t start = static_cast<size_t>(at) & mask_;
    const size_t first = n < buffer_.size() - start ? n : buffer_.size() - start;
    std::memcpy(out, &buffer_[start], first * sizeof(int16_t));
    std::memcpy(out + first, &buffer_[0], (n - first) * sizeof(int16_t));
  }

  std::vector<int16_t> buffer_;
  const size_t mask_;
  std::atomic<uint64_t> write_{0};
  std::atomic<uint64_t> read_{0};
};

}

#endif
