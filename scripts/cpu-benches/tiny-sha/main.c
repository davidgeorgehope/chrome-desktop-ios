#define _POSIX_C_SOURCE 200809L
#include "sha256.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_s(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
  /* Hash a 32 MiB buffer filled with a cheap PRNG, three times. */
  const size_t n = 32u * 1024u * 1024u;
  unsigned char *buf = (unsigned char *)malloc(n);
  if (!buf) { perror("malloc"); return 1; }
  uint32_t x = 0x12345678u;
  for (size_t i = 0; i < n; i++) {
    x = x * 1664525u + 1013904223u;
    buf[i] = (unsigned char)(x >> 24);
  }
  unsigned char out[32];
  double t0 = now_s();
  int rounds = (argc > 1) ? atoi(argv[1]) : 3;
  if (rounds < 1) rounds = 1;
  for (int r = 0; r < rounds; r++) tiny_sha256(buf, n, out);
  double dt = now_s() - t0;
  for (int i = 0; i < 32; i++) printf("%02x", out[i]);
  printf("  rounds=%d  bytes=%zu  seconds=%.6f  MiB/s=%.2f\n",
         rounds, n, dt, ((double)n * rounds / dt) / (1024.0 * 1024.0));
  free(buf);
  return 0;
}
