#ifndef FIXTURE_RINGBUFFER_HPP
#define FIXTURE_RINGBUFFER_HPP

#include <cstddef>
#include <vector>

// A tiny fixed-capacity ring buffer of integers. Deliberately small: it exists
// only to give the validator and the sanitize-check smoke test something real
// to build and exercise.
class RingBuffer {
public:
  explicit RingBuffer(std::size_t capacity);

  // Push a value, overwriting the oldest element when full.
  void push(int value);

  // Number of live elements currently stored.
  [[nodiscard]] std::size_t size() const noexcept;

  // Read element at logical index [0, size()). Out-of-range access is the
  // caller's responsibility; see the ENABLE_BUG path in the .cpp.
  [[nodiscard]] int at(std::size_t index) const;

private:
  std::vector<int> storage_;
  std::size_t capacity_;
  std::size_t head_ = 0;
  std::size_t count_ = 0;
};

#endif // FIXTURE_RINGBUFFER_HPP
