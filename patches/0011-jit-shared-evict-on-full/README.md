# Evict on full, and optional shared-cache stats

The shared translation cache is already keyed by file+offset (patch 0009)
and can slide guest PCs under ASLR. Instrumentation of a labwc+Firefox
desktop boot (`UML_JIT_SHARED_STATS=1`) showed:

- `code_page_identity` is never zero (`id0=0`). Stamps work.
- Location/slide hits work (100k–300k per boot). Reloc-cap, mapping
  slide, and a per-mm flush are not the miss cause.
- At the default `mem=4G ncpus=8` leftover (3 GiB) the cache fills at
  about 1.33M entries mid-Firefox. `reclaim_unused` then finds nothing
  to drop: every live L1 still holds a `shared_ptr` (`use_count > 1`).
  New content-process PCs also hash to different shards than the
  publisher (the shard key is the ASLR'd guest VA, not the page offset).
  Publications are rejected (`evictions=0`, `rejected` climbed to
  ~699k). Those unique blocks are never stored, so a later content
  process or a same-boot warm Firefox cannot hit them.

This patch:

1. After the unused sweep fails to make room, evicts in-use entries as
   well. Already-materialized L1 copies stay valid.
2. Walks other shards when the admission shard cannot free enough
   (`reclaim_other_shards`), so an ASLR'd lookup can admit into a
   sparsely populated shard while the 3 GiB sits in the publisher's
   shards.
3. Logs a one-second `===JIT_SHARED_STATS===` line (and an `atexit`
   dump) when `UML_JIT_SHARED_STATS` is set and not `0`.

On the instrumented side binary, rejects dropped from ~699k to ~1–3k
at the default 3 GiB cap, and insertions continued past 2M. The first
content process is not faster (it still has to compile its unique
libxul paths once). `--jit-cache-budget=8G` (about 6 GiB shared at
8 vCPUs) holds one full Firefox unique set (~2.4M entries, 5.5 GiB)
with zero evictions until a second session overflows it.

The official 4K uml-darwin binary is not replaced by this patch, and
the official identity is not bumped. Persist-to-disk of the cache was
not landed: a 2 GiB payload plus relocations and stamp versions is not
a cheap follow-up.
