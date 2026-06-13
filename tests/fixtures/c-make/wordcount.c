#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Duplicate a string onto the heap. Returns NULL on allocation failure.
static char *dup_str(const char *src) {
  size_t len = strlen(src) + 1;
  char *out = malloc(len);
  if (out == NULL) {
    return NULL;
  }
  memcpy(out, src, len);
  return out;
}

int main(void) {
  const char *words[] = {"alpha", "beta", "gamma"};
  size_t n = sizeof(words) / sizeof(words[0]);
  size_t total = 0;

  for (size_t i = 0; i < n; ++i) {
    char *copy = dup_str(words[i]);
    if (copy == NULL) {
      fprintf(stderr, "allocation failed\n");
      return EXIT_FAILURE;
    }
    total += strlen(copy);

#ifndef ENABLE_BUG
    // Correct path: release each heap copy before the next iteration.
    free(copy);
#else
    // PLANTED DEFECT (memory leak): `copy` is never freed. Build with
    // `make ENABLE_BUG=1` and run under valgrind or LeakSanitizer to see
    // "definitely lost" bytes reported, one allocation per word.
    (void)copy;
#endif
  }

  printf("total characters: %zu\n", total);
  return EXIT_SUCCESS;
}
