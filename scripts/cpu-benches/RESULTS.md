# JIT guest vs host-native CPU benches

Host: Apple M2 Pro, macOS 26.3.1, 10 cores, 16 KB pages.
Guest: `uml-darwin --execution-engine=jit`, Linux 6.18.60-g8246678b2d74, 8 vCPUs, `mem=2G`, no GPU, Alpine 3.24.2-minimal, `direct-root=yes`. Guest `/proc/cpuinfo` Features include `aes pmull sha1 sha2 sha3 sha512 crc32 atomics`.

Times are America/New_York (UTC-5). Host baseline started 10:05:51 PM ET on 12 Nov 2026 and finished 10:06:29 PM ET. Guest JIT baseline launched 10:11:50 PM ET; benches ran from guest uptime 0.88 s to 44.97 s.

## Table

| Bench | Host native | Guest JIT | Guest / host |
| --- | --- | --- | --- |
| `sh` loop 20k | 0.03 s (`/bin/dash`) | 0.31 s (Alpine ash) | 10.3× |
| `sha256sum` 32 MiB | 0.02 s (macOS coreutils, HW) | 0.38 s (busybox, software) | 19×, not a fair 1× comparison |
| openssl evp sha256, 16 KiB | 2,647,014.75k (~2,585 MB/s), OpenSSL 4.1.0, `OPENSSL_armcap=0x987d` | 1,731,317.55k (~1,691 MB/s), OpenSSL 3.5.9, `OPENSSL_armcap=0x8fd` | 1.53× |
| openssl evp aes-256-cbc, 16 KiB | 1,326,698.62k (~1,296 MB/s) | 880,214.02k (~860 MB/s) | 1.51× |
| compile tiny-sha, clang 21 `-O2` | 0.14 s | — | guest used gcc |
| compile tiny-sha, gcc `-O2` | 0.24 s (Homebrew gcc-16) | 2.78 s (Alpine gcc 15.2) | 11.6× |
| run tiny-sha 3×32 MiB, clang `-O2` | 0.380 s / 252.56 MiB/s | — | — |
| run tiny-sha 3×32 MiB, gcc `-O2` | 0.628 s / 152.90 MiB/s (gcc-16) | 1.179 s / 81.42 MiB/s (gcc 15.2) | 1.88× |
| apk add tree+openssl+build-base, offline | n/a | 3.07 s | guest-only |

Digests matched: `sha256sum` of the 32 MiB buffer is `83ee4724…`; tiny-sha digest is `bcb5fa62…` on both sides.

Fair 1× columns are openssl evp (both use ARMv8 crypto; the JIT already advertises `sha2`/`aes` and lowers them) and tiny-sha compiled with gcc. `sha256sum` on the host is hardware; Alpine busybox is software, so 19× is not a JIT tax. The shell-loop shells also differ (`dash` vs `ash`) but both are simple POSIX `while` arithmetic; 10× is still a real gap.

## Increments tried after the baseline (all reverted)

All times America/New_York (UTC-5) on 12 Nov 2026. The live `uml-darwin` tree was restored to the baseline compiler after each miss.

1. **Unsigned-run length 4/8 → 16** (about 10:15 PM ET). Within noise (evp sha256 1,731,317.55k → 1,709,888.85k; tiny-sha 81.42 → 81.00 MiB/s). Reverted. gcc `-O2` SHA-256 is mostly `LDP`/`STP`, signed/unscaled, and post-index, which that collector does not hoist.

2. **Generalized same-base runs** covering `LDP`/`STP` and signed/pre/post-index, including writeback simulation. The first encoding (pair words missing the `101` class bits) caused a guest `SIGILL` at `/init`. After fixing the class bits, `/init` hung: `sample` showed the JIT still in `run_translated_loop` / exclusives, with no serial progress. Reverted.

3. **Narrower no-writeback `LDP`/`STP` + non-negative `LDUR`/`STUR` in the existing collector**, run length 16. Same `/init` hang. Reverted.

4. **Non-negative `LDUR`/`STUR` only** (no pairs, original run lengths). Booted and finished. Results within noise (evp sha256 1,731,317.55k → 1,719,844.86k; tiny-sha 1.179 s / 81.42 MiB/s → 1.181 s / 81.28 MiB/s). Reverted: no gain. The SHA-256 offsets that matter are negative (`[x1, #-60]` etc.).

5. **One-entry last-page host-delta cache** in `JitChainState`, checked in `emit_translate` before the 512 KiB software TLB. Booted and finished, but a regression: tiny-sha 81.42 → 78.45 MiB/s, evp sha256 1,731,317.55k → 1,691,828.22k, sh loop 0.31 → 0.35 s. The extra compare+branch on every access cost more than the hit saved, especially when the working set alternates pages. Reverted.

The guest/host table above is unchanged. Indirect-branch ICs (still 2-entry), a RET stack, cheaper SVC exits, and a correct LDP/signed-offset hoist remain unlanded.


## Exit profile (12 Nov 2026, 10:49–10:50 PM ET)

Added a default-off translated-block profiler (`UML_JIT_PROFILE=1`, patch `patches/0005-jit-exit-profile.patch`). It counts `run_block` entries by cache hit/miss/shared reuse, compile time of new blocks, and exits by reason (SVC, indirect miss, continued/unlinked-or-fairness, page fault, IRQ). A control file can reset or dump mid-run. Disabled, the cost is one predictable branch per block entry/exit.

Counters below were isolated by resetting after boot (and after `apk add` for the compile) and snapshotting immediately after the bench, with `script -F` so the host saw the marks live. Raw files: `scripts/cpu-benches/profiles/`.

### `sh` loop 20k (0.37 s wall with the profiler on; baseline without it was 0.31 s)

| Counter | Count | Share of `run_blocks` |
| --- | ---: | ---: |
| `run_blocks` | 3,263,109 | 100% |
| cache hit | 3,259,668 | 99.9% |
| cache miss / compile | 3,442 / 3,416 | 0.1% |
| compile time | 16.3 ms (avg 4.8 µs/block) | — |
| shared reuse | 0 | — |
| exit continued (fairness or unlinked direct / ISB / etc.) | 1,918,633 | 58.8% |
| exit indirect miss | 1,344,306 | 41.2% |
| exit SVC | 80 | ~0% |
| exit page fault | 91 | ~0% |
| exit IRQ | 0 | 0% |

The 10× shell tax is not syscalls or compile. Almost every translated block returns to C++ because the chain could not stay in generated code: either the 2-entry indirect cache missed (typically `RET` / indirect calls) or a direct link took the continued fallback (fairness window or an unlinked successor). 3.26 million `run_block` entries in 0.37 s is ~113 ns per entry, which already accounts for the whole bench.

### compile tiny-sha, gcc `-O2` (2.98 s wall with the profiler on; baseline without it was 2.78 s)

| Counter | Count | Share |
| --- | ---: | ---: |
| `run_blocks` | 5,538,113 | 100% of entries |
| cache hit | 4,855,643 | 87.7% |
| cache miss / compile | 682,470 / 681,564 | 12.3% of entries |
| compile time | **1,396 ms** | **47% of wall** |
| shared reuse | 0 | — |
| exit continued | 2,952,628 | 53.3% of entries |
| exit indirect miss | 2,565,360 | 46.3% of entries |
| exit SVC | 7,897 | 0.14% |
| exit page fault | 12,228 | 0.22% |
| exit IRQ | 0 | 0% |

The 11.6× compile tax is two problems stacked. First, this one-shot `gcc`/`cc1`/`as` run compiled 681k new blocks (1.40 s). The process-wide shared translation cache did not reuse any of them: publications require two live executors at once, and entries are keyed by guest PC + words, so ASLR after `exec` misses even when the bytes are the same (`libc`, the dynamic linker, `libgcc`). Second, the blocks that do hit still exit the same way the shell does (continued + indirect miss). SVC is not the top exit on either bench.

## Next costs

- Shell (~10×): a return-address stack plus a deeper polymorphic inline cache for indirect sites (they are still 2-entry), and a split of `exit.continued` into fairness vs unlinked-direct so those chains stay in generated code.
- Compile (~11.6×): persist or share translations across `fork`/`exec` of the same file, keyed by file+offset (or a fixed guest-user mapping so PCs are stable). Also allow the shared cache to publish when only one executor is live, which is how a sequential toolchain actually runs. Cheaper SVC round trips are not the top cost here (7,897 SVC exits vs 1.40 s of compile and millions of continued/indirect exits).
- Software CPU (~1.88×): left alone for now. A correct hoist of `LDP`/`STP` and signed/post-index still needs a unit test first (the naive run hung `/init`); a multi-entry last-page cache must not tax the miss path.
- A fixed host offset for guest user memory (the Darwin native window and `direct-root` already map guest physical RAM) was not implemented; it needs a conflict-free VA plan on 16 KiB host pages. A design belongs in `DESIGN.md`.
