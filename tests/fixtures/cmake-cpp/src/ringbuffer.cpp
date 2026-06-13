#include "ringbuffer.hpp"

RingBuffer::RingBuffer(std::size_t capacity)
    : storage_(capacity), capacity_(capacity) {}

void RingBuffer::push(int value) {
  storage_[head_] = value;
  head_ = (head_ + 1) % capacity_;
  if (count_ < capacity_) {
    ++count_;
  }
}

std::size_t RingBuffer::size() const noexcept { return count_; }

int RingBuffer::at(std::size_t index) const {
#ifdef ENABLE_BUG
  // PLANTED DEFECT (heap-buffer-overflow): no bounds check, and we index the
  // backing store by the raw logical index. Calling at(size()) or beyond
  // reads past the live region — AddressSanitizer flags this as a
  // heap-buffer-overflow. Build with -DENABLE_BUG=ON to expose it.
  return storage_[index];
#else
  // Correct path: clamp to the live region so out-of-range reads are defined.
  std::size_t safe = index < count_ ? index : (count_ == 0 ? 0 : count_ - 1);
  std::size_t physical = (head_ + capacity_ - count_ + safe) % capacity_;
  return storage_[physical];
#endif
}
