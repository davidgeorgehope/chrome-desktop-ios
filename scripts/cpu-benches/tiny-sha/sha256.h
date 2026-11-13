#ifndef TINY_SHA256_H
#define TINY_SHA256_H
#include <stddef.h>
#include <stdint.h>
void tiny_sha256(const void *data, size_t len, unsigned char out[32]);
#endif
