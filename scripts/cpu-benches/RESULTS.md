# JIT guest vs host-native CPU benches

Host: Apple M2 Pro, macOS 26.3.1, 10 cores, 16 KB pages.
Guest: `uml-darwin --execution-engine=jit`, Linux 6.18.60-g8246678b2d74, 8 vCPUs, `mem=2G`, no GPU, Alpine 3.24.2-minimal, `direct-root=yes`. Guest `/proc/cpuinfo` Features include `aes pmull sha1 sha2 sha3 sha512 crc32 atomics`.

Times are America/New_York (UTC-5). Host baseline started 10:05:51 PM ET on 12 Nov 2026 and finished 10:06:29 PM ET. Guest JIT baseline launched 10:11:50 PM ET; benches ran from guest uptime 0.88 s to 44.97 s.

## Table

| Bench | Host native | Guest JIT | Guest / host |
| --- | --- | --- | --- |
| `sh` loop 20k, dash | 0.03 s (macOS `/bin/dash`) | 0.19 s (Alpine dash 0.5.13.1) | **6.3×** |
| `sh` loop 20k, ash | — (Linux busybox cannot run on macOS) | 0.20 s (Alpine busybox ash) | not like-for-like |
| native-loop 200M `++`, gcc `-O2` | 0.39 s (Homebrew gcc-16) | 0.49 s (Alpine gcc 15.2) | **1.26×** |
| `sha256sum` 32 MiB | 0.02 s (macOS coreutils, HW) | 0.38 s (busybox, software) | 19×, not a fair 1× comparison |
| openssl evp sha256, 16 KiB | 2,647,014.75k (~2,585 MB/s), OpenSSL 4.1.0, `OPENSSL_armcap=0x987d` | 1,731,317.55k (~1,691 MB/s), OpenSSL 3.5.9, `OPENSSL_armcap=0x8fd` | 1.53× |
| openssl evp aes-256-cbc, 16 KiB | 1,326,698.62k (~1,296 MB/s) | 880,214.02k (~860 MB/s) | 1.51× |
| compile tiny-sha, clang 21 `-O2` | 0.14 s | — | guest used gcc |
| compile tiny-sha, gcc `-O2`, cold | 0.24 s (Homebrew gcc-16) | 1.87 s (Alpine gcc 15.2) | **7.8×** |
| compile tiny-sha, gcc `-O2`, warm | 0.24 s (Homebrew gcc-16) | 1.09 s (Alpine gcc 15.2) | **4.5×** |
| run tiny-sha 3×32 MiB, clang `-O2` | 0.380 s / 252.56 MiB/s | — | — |
| run tiny-sha 3×32 MiB, gcc `-O2` | 0.628 s / 152.90 MiB/s (gcc-16) | 1.179 s / 81.42 MiB/s (gcc 15.2) | 1.88× |
| apk add tree+openssl+build-base, offline | n/a | 3.07 s | guest-only |

Digests matched: `sha256sum` of the 32 MiB buffer is `83ee4724…`; tiny-sha digest is `bcb5fa62…` on both sides.

Fair 1× columns are openssl evp (both use ARMv8 crypto), tiny-sha compiled with gcc, the gcc-built native loop, and the 20k loop run with dash on both sides. `sha256sum` on the host is hardware; Alpine busybox is software, so 19× is not a JIT tax. Host `/bin/sh` is bash 3.2 (0.07 s on the same loop) and cannot be compared to Alpine ash; Linux busybox cannot run on macOS, so ash is guest-only. evp and tiny-sha-run numbers are still the 10:11 PM ET baseline. Dash, ash, native-loop, and compile (cold and warm) were re-timed at 11:41–11:42 PM ET on 12 Nov 2026 with the shared-translation cache landed; see below.

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

## Direct links, fairness underflow, and an A64 indirect table (12 Nov 2026, 11:06–11:09 PM ET)

Patch `patches/0006-jit-direct-and-indirect-links.patch` (full sources in `patches/0006-jit-direct-and-indirect-links/`). Three changes, measured together because the first two have to land as a pair and the third was already wired in the same tree:

1. **Full chain capabilities.** A no-store / no-FP entry block used to advertise selector 0, so a compiled store or FP successor failed the `allowed_selectors` check and every such direct branch returned to C++ (1.38M of 1.92M `continued` exits on the shell). The executor now opens `JitBlockPublication` for every chain and materializes FP + the native FP environment at entry, so the selector is 5 whenever stores do not need tracking. While a reservation is live and the entry block itself has no stores, store publication is still not advertised.

2. **Fairness no longer wraps.** The remaining-instruction counter already decremented toward the 4096-instruction budget, but the subtract did not set flags. When remaining was smaller than the just-finished block, `x20` underflowed to a huge unsigned value, the `remaining < successor.instruction_count` check never fired, and well-linked tight loops (observed: `grep | sort` of `/proc/cpuinfo`) ran without returning to C++, so timers and RCU stalled. Direct and indirect links now use `SUBS` and take the fairness fallback on unsigned underflow. After the fix, the shell shows 20,094 fairness exits and no stalls.

3. **In-JIT A64 indirect hash.** Behind each site's 2-cell inline cache, generated A64 `BR`/`BLR`/`RET` looks up an 8192-entry per-executor direct-mapped table (keyed by the target PC, guarded by the chain's link epoch). A hit stays in generated code; a miss still returns to C++ to train the table. There is not yet a return-address stack, and the per-site IC is still 2-entry.

Timing with the profiler off, two clean boots (11:07 and 11:08 PM ET):

| Bench | Before (baseline) | After (run 1 / run 2) |
| --- | ---: | ---: |
| `sh` loop 20k | 0.31 s (10.3×) | **0.25 s / 0.26 s** (**8.3× / 8.7×**) |
| compile tiny-sha, gcc `-O2` | 2.78 s (11.6×) | 2.90 s / 2.94 s (12.1× / 12.3×) |

The table at the top uses isolated dash 0.24 s (fair) and compile 2.92 s. The ash-loop cut from 0.31 s to 0.26 s is a verified gain; the like-for-like dash figure is 8.0×. The compile is slightly slower: new-block translation is still ~1.31 s (45% of wall), and always-on publication + FP setup is paid on every chain entry. A first attempt at (1) without (2) hung the guest in `grep`/`sort` with `rcu_sched` stalls and was not landed on its own.

### `sh` loop 20k after the change (0.26 s wall with the profiler on)

| Counter | Count | Share of `run_blocks` |
| --- | ---: | ---: |
| `run_blocks` | 259,229 | 100% (was 3,263,109) |
| cache hit | 254,188 | 98.1% |
| cache miss / compile | 5,041 / 5,000 | 1.9% |
| compile time | 19.1 ms | — |
| shared reuse | 0 | — |
| exit continued | 257,568 | 99.4% |
| — of which fairness | 20,094 | 7.8% |
| — uncompiled | 5,838 | 2.3% |
| — unsafe (reservation split) | 84,653 | 32.7% |
| — nonlink (ISB / helpers / etc.) | 146,982 | 56.7% |
| — selector store / FP | 1 / 0 | ~0% |
| exit indirect miss | 1,378 | 0.5% (was 1,344,306 / 41.2%) |
| exit SVC | 127 | ~0% |
| exit page fault | 156 | ~0% |
| exit IRQ | 0 | 0% |

Raw: `scripts/cpu-benches/profiles/profile-sh_loop-links.txt`. Retired ~308M guest instructions, same work as before, in 12.6× fewer `run_block` trips. Selector mismatches are gone. Indirect misses are essentially gone. The leftover `continued` exits are mostly non-link cuts and reservation-split targets, plus a working fairness window.

### compile tiny-sha, gcc `-O2` after the change (2.91 s wall with the profiler on)

| Counter | Count | Share of `run_blocks` |
| --- | ---: | ---: |
| `run_blocks` | 1,018,048 | 100% (was 5,538,113) |
| cache hit | 388,573 | 38.2% |
| cache miss / compile | 629,475 / 628,670 | 61.8% |
| compile time | **1,311 ms** | **45% of wall** |
| shared reuse | 0 | — |
| exit continued | 800,988 | 78.7% |
| — of which uncompiled | 636,325 | 62.5% |
| — fairness | 78,593 | 7.7% |
| — unsafe | 28,437 | 2.8% |
| — nonlink | 56,593 | 5.6% |
| — selector FP / store | 1,040 / 0 | 0.1% |
| exit indirect miss | 201,749 | 19.8% (was 2,565,360 / 46.3%) |
| exit SVC | 5,199 | 0.5% |
| exit page fault | 10,113 | 1.0% |
| exit IRQ | 0 | 0% |

Raw: `scripts/cpu-benches/profiles/profile-compile-links.txt`. Execution exits dropped sharply, but this bench still spends 1.31 s compiling ~629k new blocks with no shared-cache reuse across `gcc`/`cc1`/`as`, so wall time does not improve.

## Fair shell and a tight C loop (12 Nov 2026, 11:14–11:18 PM ET)

The 8.7× shell figure compared host `/bin/dash` to guest busybox ash. Isolated timings with the same dash on both sides, profiler off, three runs, no toolchain pack first (raw: `scripts/cpu-benches/profiles/fair-timings.txt`):

| Side | dash 20k | ash 20k |
| --- | ---: | ---: |
| Host (macOS) | 0.03 s, 0.03 s, 0.03 s | n/a |
| Guest JIT, isolated | **0.24 s, 0.24 s, 0.24 s** | 0.26 s, 0.27 s, 0.25 s |

Like-for-like dash is **8.0×**, not 8.7×. Guest dash is slightly faster than guest ash; the earlier comparison was a little unfair *against* the JIT. After a full `apk add` of the toolchain the same loops were 0.42 s / 0.40 s — not used in the table; the extra packages pollute the translation cache.

A tight C loop (`volatile unsigned long i = 0; while (i < 200000000UL) ++i;`, gcc `-O2`) is the better "pure JIT" ratio, because it is the same source compiled on each side:

| Compiler | Host | Guest JIT | Ratio |
| --- | ---: | ---: | ---: |
| gcc (`gcc-16` vs Alpine gcc 15.2) | 0.39 s | 0.57 s | **1.46×** |
| clang `-O2` on the host only | 0.06 s | — | not a fair pair (guest has gcc) |

1.46× sits with openssl evp (~1.5×) and gcc-built tiny-sha (1.88×). The remaining shell gap is therefore not "the JIT is 8× on ordinary integer code." Block entries already dropped 12× and only moved the ash loop from 0.31 s to 0.26 s; a tight compiled loop is already near the memory-tax band. What is still slow is the shell interpreter itself (very branchy, lots of non-link and reservation-split exits) rather than C++ block dispatch.

## Shared translations, not landed (12 Nov 2026, 11:17 PM ET)

DESIGN.md step 4 was tried: allow the process-wide shared cache to publish with a single live executor (it already keeps unused entries after an executor exits, evicting only under budget). Guest ASLR was turned off (`randomize_va_space=0`) so a PC+words key could hit across `gcc` → `cc1` → `as` and on a second compile.

It did not help. `compile_tiny_sha` was 3.10 s cold and 3.04 s warm (slightly *worse* than the landed 2.92 s). A profiler snapshot of both compiles showed `shared.insertions=58`, `shared.reuses=694`, `shared.misses=1,696,147`, `compile_ms=3,116`. Almost every new block is still compiled privately: `publish_shared_translation` refuses a translation whose literal-pool link pointer had to fall back to a host-baked MOV-wide (`!compiled.relocatable`), so the cache never sees the ~1.5M compiles. The two-executor gate was not the binding constraint. The change was reverted and not committed. File+offset / content-hash keys plus a slide of baked guest PCs, and making link literals stay relocatable, are still required before a warm `cc1` can go toward zero compile time.

## Shared translations landed (12 Nov 2026, 11:26–11:42 PM ET)

`patches/0007-jit-shared-translations/`. Official timings, profiler off, ASLR off for compiles (`randomize_va_space=0`). Raw: `scripts/cpu-benches/profiles/shared-translation-timings.txt` and `profile-compile-shared-translations.txt`.

Three things were needed together. A relocatable literal island replaced the host-baked MOV-wide fallback for out-of-range link pointers, so publications stay sharable. The shared cache may now publish with a single live executor, which is what sequential `gcc` → `cc1` → `as` actually has. And the default whole-process JIT budget now funds the 256 MiB private cap of every vCPU *and* leaves 2 GiB for the shared cache: with `mem=2G` `ncpus=8` the old default of guest/2 was entirely consumed by the eight L1s, so `publish_shared_translation` rejected 1.69M of 1.69M admits (`shared.rejected=1688136`, 81 insertions, 26 live entries). With room, a cap of two relocations still rejected 145k unique gcc blocks (`shared.malformed.reloc_count`); raising it to `maximum_block_instructions` (64) dropped malformed to 0.

Cold+warm profile (profiler on, isolated compile path, after the cap raise):

| Counter | Cold compile | Cold+warm+native-loop |
| --- | ---: | ---: |
| wall | 1.86 s | 1.86 + 1.10 + 0.21 s |
| `compiles` | 130,319 | 130,864 |
| `compile_ms` | 554 | 557 |
| shared insertions / entries | 237,779 | 238,316 |
| shared reuses | 207,331 | 595,878 |
| shared rejected / malformed | 0 / 0 | 0 / 0 |
| accounted / maximum | 538 MiB / 2.00 GiB | 539 MiB / 2.00 GiB |

Warm compile time is essentially zero (3 ms more compile). The remaining 1.09 s of warm wall is execution, not translation. Intra-compile reuse already cuts the first compile's compile time from 1.31 s to 0.55 s (`cc1`/`as` sharing libc and the toolchain at the same VA with ASLR off). File+offset / content-hash keys and a slide of baked guest PCs were not added; a warm `cc1` under ASLR would miss the PC+words key. A cheaper first-tier or lazy-hot-only compile was not tried: after sharing, cold compile is 0.55 s of a 1.87 s wall, and warm is no longer compile-bound.

The same budget change grows each private L1 from ~128 MiB to 256 MiB. Isolated dash improved as a side effect (median 0.24 s → 0.19 s, **6.3×** vs host 0.03 s; ash 0.26 s → 0.20 s). The tight gcc loop went from 0.57 s to 0.49 s (**1.26×** vs host 0.39 s).

Host sampling of the shell: `dtrace` is denied (SIP). `sample` hung previously (target already exited, and/or a TCC prompt that was not touched) and was not captured this pass; there is no `/usr/bin/timeout` on the Mac, so a second 8 s sample missed the 14.5 s window. A 1.6M-iteration dash loop was 14.50 s real, 14.48 user, 0.02 sys in the guest. Host `/usr/bin/time -l` around the whole `uml-darwin` (boot + apk + loop + poweroff) was 16.08 s real, 15.41 user, 0.67 sys, 17 page faults, 68,068 page reclaims. The leftover 6.3× is userspace in the interpreter (non-link cuts, reservation splits, fairness), not UML kernel time, COW, or timer IRQs. No further shell-exit change was landed in this pass.


## File+offset shared cache under ASLR (13 Nov 2026, 12:36–12:52 AM ET)

`patches/0008-jit-sigprof/` and `patches/0009-jit-file-offset-aslr/`.
Simulator work was left alone (CoreSimulator still wedged; needs a mini
reboot). The unused exclusive-pair codegen test and its `engine.cmake`
entry were dropped and not committed.

### SIGPROF dash histogram

`UML_JIT_SIGPROF=1` at 99 Hz on a 1.6M-iteration dash loop (14.46 s real,
14.41 user). The first dump was lost because `darwin_uml_exit()` uses
`_exit()` and skipped `atexit`; the sampler now dumps from that path and
from a 1 s flusher, still default off.

Final histogram: `samples=1411` `dropped=0` `unique=1092`. 79.7% of
samples are in JIT generated code, spread across 919 unique PCs, with no
cluster above 2.5%. The top libc hits (memset 27, an unsybolized
`0x6000002ec0cc` at 15) did not grow after boot, so the dash loop itself
is almost entirely generated code. `run_block` is ~2% and
`jit_profile::enabled` is 0.8% even with profiling off. There is no
clear, safe C++ hotspot for the remaining 6.3×; it is codegen quality of
the dash interpreter loop. Raw: `scripts/cpu-benches/profiles/uml-jit-sigprof-dash.txt`
and `uml-jit-sigprof-dash.analysis.txt`.

### File+offset keys and a slide of baked guest PCs

Shared translations stay keyed by guest PC + words for same-VA hits, and
are also indexed by the host code-page stamp (stable for one physical
backing page) plus the guest page offset. `store_pc`, ADR/ADRP, BL
return, and indirect-site keys are `JitRelocationKind::guest_pc`
literals, slid by `new_pc - recorded_pc` at materialization.

The first ASLR-on boot after only `store_pc` was relocated segfaulted in
`ld-musl` (same data address `0x7fffbd8ced68` from two processes at
different load bases). Recording ADR/ADRP and the leftover PC literals
fixed it.

Official-like timings, profiler off, ASLR **left on** (`randomize_va_space=1`).
Raw: `scripts/cpu-benches/profiles/aslr-file-offset-timings.txt`. A
profiled compile (boot + apk + cold + warm) is
`scripts/cpu-benches/profiles/profile-compile-aslr-file-offset.txt`.

| Bench | This run (ASLR on) | 12 Nov official (ASLR off) | Host native (prior) | Ratio vs native |
| --- | ---: | ---: | ---: | ---: |
| `sh_loop_dash` (20k) | 0.18 s | 0.19 s | 0.03 s | **6.0×** |
| `compile_tiny_sha` cold | 2.12 s | 1.87 s | 0.24 s | **8.8×** |
| `compile_tiny_sha` warm | 1.22 s | 1.09 s | 0.24 s | **5.1×** |

Before this change a warm `cc1` under ASLR missed the PC+words key and
looked like a cold compile. Warm wall is now close to the ASLR-off figure,
i.e. mostly execution. A profiled compile showed `shared.reuses=513,919`,
`shared.insertions=171,055`, `compile_ms=814` (process lifetime, including
boot and apk). 8,909 publications were rejected for `reloc_count` now that
blocks carry extra guest-PC slots; the cap is still `maximum_block_instructions`.
That leftover, plus leaving ASLR on, is why warm wall is 1.22 s rather than
1.09 s. vkcube / Venus was not diagnosed in this pass.

### Relocation cap raised above 64 (`patches/0010-jit-reloc-cap`)

Guest-PC literals from 0009 made a 64-instruction block need more than 64
relocatable slots. The cap is now `maximum_block_instructions * 2 + 4`
(132). A profiled compile dropped `shared.malformed.reloc_count` from
8,909 to 0 and `compile_ms` from 814 to 683. Raw official-like numbers,
profiler off, ASLR left on:
`scripts/cpu-benches/profiles/reloc-cap-timings.txt`.

| Bench | 0010 (ASLR on) | 0009 (ASLR on) | 12 Nov official (ASLR off) | Host native (prior) | Ratio vs native |
| --- | ---: | ---: | ---: | ---: | ---: |
| `sh_loop_dash` (20k) | 0.18 s | 0.18 s | 0.19 s | 0.03 s | **6.0×** |
| `compile_tiny_sha` cold | 2.07 s | 2.12 s | 1.87 s | 0.24 s | **8.6×** |
| `compile_tiny_sha` warm | 1.16 s | 1.22 s | 1.09 s | 0.24 s | **4.8×** |
| `native_loop` (tight gcc loop) | 0.49 s | not re-run | 0.49 s | ~0.39 s | **1.26×** |
| run tiny-sha 3×32 MiB, gcc `-O2` | 1.182 s / 81.22 MiB/s | not re-run | 1.179 s / 81.42 MiB/s | 0.628 s / 152.90 MiB/s | **1.88×** |
| openssl evp sha256, 16 KiB | 1,777,931.61k | not re-run | 1,731,317.55k | 2,647,014.75k | **1.49×** |
| openssl evp aes-256-cbc, 16 KiB | 1,029,865.47k | not re-run | 880,214.02k | 1,326,698.62k | **1.29×** |

Compile rows are from an isolated official-like boot (dash + compile only),
the same protocol as 0009. The tight loop, tiny-sha-run, and evp numbers
are from a full official-like suite on the same binary, ASLR on, OpenSSL
3.5.9 `OPENSSL_armcap=0x8fd`. evp aes-256-cbc is faster than the earlier
10:11 PM ET baseline; tiny-sha-run and the tight loop are within noise of
that baseline. The cap raise itself is the modest warm-compile win
(1.22 s → 1.16 s).

A first `UML_JIT_USER_MAP=1` prototype of the `DESIGN.md` fixed-offset
guest user mapping reserved 32 × 32 GiB slots, booted, and ran apk, dash,
and gcc, but regressed dash to 0.29 s and warm compile to 1.46 s. It was
not committed. Blockers (native window layout, 47-bit host vs high PIE,
16 KiB vs 4 KiB pages) are in `DESIGN.md`.

## Next costs

- Shell (fair dash still **6.0×**): SIGPROF on a 1.6M-iteration loop put 80% of samples in generated JIT code, with no single C++ hotspot. The leftover is still the per-load/store translation sequences in generated code, plus interpreter control flow (non-link cuts, reservation splits, fairness). The first fixed-offset mapping prototype booted but regressed this number; see `DESIGN.md`.
- Compile is **8.6×** cold and **4.8×** warm with ASLR on, after raising the reloc cap so the 8,909 overflowing blocks publish (`patches/0010-jit-reloc-cap`). Warm wall is 1.16 s, closer to the 1.09 s ASLR-off figure, and is still mostly execution. A 999 Hz SIGPROF of the compile-cold window later showed decode/emit/`compile_once` are only ~4%; host malloc, memmove, and shared-cache validation dominate. `patches/0012-jit-publish-alloc` packs each publication and skips the duplicate shape check: compile-cold 2.06–2.07 s → 1.96–1.98 s on a side binary. The official 4K identity was not bumped.
- Software CPU is unchanged in substance: tight loop **1.26×**, evp sha256 **1.49×**, tiny-sha-run **1.88×**. evp aes-256-cbc re-timed at **1.29×** (was 1.51× on the earlier baseline; treat as a re-measurement, not a cap-raise claim). A correct hoist of `LDP`/`STP` and signed/post-index still needs a unit test first.
- A fixed host offset for guest user memory remains the lever for the 1.5–1.9× memory tax and much of the shell gap, but the first prototype is not that win yet.
