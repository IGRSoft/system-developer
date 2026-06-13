#include "ringbuffer.hpp"

#include <gtest/gtest.h>

// Passing test exercising the default (non-buggy) path. With -DENABLE_BUG=ON
// the at() implementation reads out of bounds and AddressSanitizer reports a
// heap-buffer-overflow when this test runs.
TEST(RingBufferTest, StoresAndReadsBack) {
  RingBuffer rb(3);
  rb.push(10);
  rb.push(20);
  rb.push(30);

  EXPECT_EQ(rb.size(), 3u);
  EXPECT_EQ(rb.at(0), 10);
  EXPECT_EQ(rb.at(2), 30);
}

TEST(RingBufferTest, OverwritesOldestWhenFull) {
  RingBuffer rb(2);
  rb.push(1);
  rb.push(2);
  rb.push(3); // overwrites the oldest (1)

  EXPECT_EQ(rb.size(), 2u);
  EXPECT_EQ(rb.at(0), 2);
  EXPECT_EQ(rb.at(1), 3);
}
