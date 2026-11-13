/* Tight integer loop for a like-for-like JIT vs host-native ratio.
 * volatile so the increment is not optimized out. */
int main(void) {
  volatile unsigned long i = 0;
  while (i < 200000000UL)
    ++i;
  return (int)(i >> 32);
}
