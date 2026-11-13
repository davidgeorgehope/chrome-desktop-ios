# Bump arena for packed SharedTranslation publications

Packed publish (0012) still called `make_shared` for the `SharedTranslation`
object and `make_shared_for_overwrite` for the packed payload on every
cold publication. Those two heap hits, plus the later `shared_ptr` control
block, were a large part of the compile-cold malloc/memmove cost.

This patch, on top of evict-on-full (0011) and packed publish (0012):

1. Allocates the `SharedTranslation` object, guest identity, host words, and
   relocations from one block in a process-wide bump arena of recycled 1 MiB
   chunks. Publication is a thread-local bump (no lock on the fast path).
2. The returned `shared_ptr` and `guest_words` alias that block (one control
   block). The deleter destroys the object and drops the chunk's live count.
   When the last publication in a retired chunk is evicted, the chunk returns
   to a free list and is reused as a whole.
3. Uniquely cached publications now have `use_count() == 2` (cache entry plus
   the `guest_words` member). Evict-on-full treats that as unused; an L1 pin
   of either pointer raises both counts together.

Host words are still memcpy'd from the compiler's emit buffer into the
published pack (sizes are only known after emit). A later change could emit
straight into a pre-sized arena block; this patch removes the per-publication
heap traffic, not that one copy.

Measured on a side `uml-darwin-arena` (official 4K inode unchanged,
profilers off, same session as official and packed-publish):

See NOTES.md for the compile-cold / apk add / Isolated Web Content table.
The official identity was not bumped unless that table and a clean full
CPU-suite comparison justified it.

## iOS / Simulator apply

These three files are the iOS-applicable series: evict-on-full (0011),
packed publish (0012), and this bump arena, already folded together.
Copy them over `darwin/cpu/arm64/jit/` as a set. The iPhoneSimulator
26.5 SDK also needs `patches/0014-simulator-vm-region-64`. The
reproducible apply and build is `scripts/build-kernarium-simulator.sh`.
Do not install the resulting app on a physical iPhone. Do not rebuild
the official macOS `uml-darwin` identity from the copied sources.
