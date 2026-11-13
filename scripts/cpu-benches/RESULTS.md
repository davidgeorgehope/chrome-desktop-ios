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

## First increment (not kept)

Raised the JIT unsigned-offset memory-run cap from 4 (GPR/SP) / 8 (SIMD) to 16 and `RunStraddle::maximum_accesses` to 16, so more consecutive same-base unsigned loads/stores share one TLB lookup and run as the guest's own `LDR`/`STR`. Re-measured at 10:15 PM ET. Results were within noise (openssl sha256 evp 16 KiB 1,731,317.55k → 1,709,888.85k; tiny-sha 1.179 s / 81.42 MiB/s → 1.185 s / 81.00 MiB/s). The change was reverted. gcc `-O2` SHA-256 is dominated by `LDP`/`STP`, signed/unscaled offsets, and post-index, which this run collector does not cover.

## Next costs

- Software CPU (~1.88×): hoist translation for pair and signed/post-index accesses, or a last-page host-delta cache so translated memory is not redone on every access.
- Shell loop (~10×): richer indirect-branch inline caches (sites are still 2-entry) and longer chained blocks.
- Compile (~11.6×): cold per-exec translation plus syscall exits (SVC still terminates the block with `Event::system_call`).
