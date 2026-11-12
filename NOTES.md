# Linux-in-iOS Simulator bakeoff

Date: Thu Nov 12, 2026, evening ET (America/New_York).
Host: mac.lan (Darwin 25.3.0, arm64 T6020). Xcode 26.6, iOS 26.5 Simulator "Peek iPhone 17" (UDID 8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB).
Work dir: ~/linux-ios-bakeoff. Simulator only. Nothing was installed on the iPhone.
Caveat: the Simulator runs guest code on the Mac's Apple Silicon, so absolute numbers are much faster than a phone. The JIT numbers below also use a Simulator-only MAP_JIT path that a physical iPhone does not have unless a debugger (StikDebug) is attached. Use the gadget-engine column as the "no debugger on device" estimate.

Security: third-party trees were scanned before building (see notes/security-scan.txt). No exfiltration or surprise persistence turned up.

## Profile: where Kernarium's time went

The first Kernarium run (6:34–6:35 PM ET) was only ~1.13–1.35× LinuxRunner on the CPU/package benches. That was not a "native userspace" run.

Kernarium has two arm64 userspace engines:

- **Gadget engine** — a threaded-code / precompiled-gadget interpreter. Always available. This is what the first run used.
- **JIT engine** — compiles guest AArch64 to host AArch64 into a MAP_JIT (or debugger-blessed) arena. Built for the Simulator runtime (`UML_ARM64_JIT_ENGINE` is on unless it is an App Store build), but upstream leaves it off in the Simulator on purpose: `jit_publication_supported()` is compiled out because the iOS SDK marks `pthread_jit_write_protect_np` unavailable, `use_jit` in `ContentView.swift` was left 0, and the default `--execution-engine=auto` resolves to gadgets (`UML_DEFAULT_EXECUTION_ENGINE_JIT` is only on for macOS). G157 rejected Simulator JIT for the GPU-bound WebGL Aquarium; that measurement was not about these CPU benches.

Evidence the first run was on gadgets: no `use_jit` in the boot request, no "execution engine jit" line, and no "running on gadgets" warning (that warning only prints when JIT was requested and failed).

Hugepage / mmap / cheaper syscalls / kernel-config trimming were not the first-order cost: the guest userspace itself was being interpreted. After the JIT was on, OpenRC boot got slower (translation warmup, 4.86 s → 9.99 s to bench start), so the next largest cost was init, not the kernel window or console.

This local fork:

1. Enables the Simulator MAP_JIT publication route via `dlsym("pthread_jit_write_protect_np")` (the symbol exists in the Simulator process).
2. Sets `request.use_jit = 1` and logs the selected engine. A successful prepare reported `execution engine jit (cache budget 1073741824 bytes)`.
3. Skips OpenRC: inittab runs `/bin/mount -a` then the bench script, which brings up DHCP itself.

A light desktop was not added. The Simulator uses llvmpipe, not KosmicKrisp/Metal; putting Weston or a similar compositor on the 402×778 software framebuffer is not a cheap change, and the stop condition (a measured ≥2× on the CPU benches) was already met.

## Side-by-side benches (same Simulator, same Alpine 3.24.2)

LinuxRunner: JIT/VIRGL off, 5:12–5:26 PM ET.
Kernarium gadgets: 6:34–6:35 PM ET, OpenRC init.
Kernarium JIT + OpenRC: 6:45–6:46 PM ET (boot slower from JIT warmup).
Kernarium JIT + slim init (current): 6:47–6:48 PM ET, serial log `notes/kernarium-sim-launch-jit-slim.log`. Official numbers for the "after" column.

| Bench | LinuxRunner | Kernarium gadgets | Kernarium JIT + slim init | JIT vs LinuxRunner |
| --- | --- | --- | --- | --- |
| Boot to a usable userspace (guest uptime at first payload; wall clock is higher by app start) | ~3.2 s to terminal frontend (shell scheduled at ~229 ms) | 4.86 s to auto-benches, ~7 s wall to autologin with OpenRC | **1.00 s** to auto-benches (DHCP already up) | Faster to a running shell than LinuxRunner's terminal load |
| `sh` loop, 20,000 increments | 1.03 s | 0.79 s | **0.34 s** | **3.03×** |
| Write 32 MiB (`dd` to a file) | 523.6 MB/s | 1.7 GB/s | 2.2 GB/s | ~4.2× |
| `sha256sum` of that 32 MiB | 1.64 s (~19.5 MB/s) | 1.45 s | **0.38 s** (~84 MB/s) | **4.32×** |
| `apk add --no-cache tree` | 3.08 s (user 2.08 s) | 2.35 s | **1.49 s** (user 0.88 s) | **2.07×** wall / ~2.4× user |
| `apk add --no-cache openssl` | 3.39 s (user 2.32 s) | 2.51 s | **1.58 s** (user 1.00 s) | **2.15×** wall / ~2.3× user |
| `openssl speed -evp` at 16 KiB | aes 169.3 MB/s; sha256 376.0 MB/s | aes 164.0; sha256 594.9 | **aes 875.1 MB/s; sha256 1696.3 MB/s** | **5.17× / 4.51×** |

JIT + OpenRC (without slim init) already had sh 0.33 s, sha256 0.39 s, apk 1.67 / 1.67 s, aes 872.8 / sha256 1685.6 MB/s. Slim init did not change the CPU numbers in any important way; it cut boot and trimmed a little off apk (less stuff running). Host OpenSSL 4.1.0 on the same Mac was 1294 / 2573 MB/s, so the JIT guest is about two-thirds of native for those evp numbers.

Guest identity (slim init): `Linux (none) 6.18.60-gf89b4c310c47` aarch64, Alpine 3.24.2. Hostname is `(none)` because OpenRC's hostname service was skipped.

Screenshots (box `/workspace/`, also on the mini under `~/linux-ios-bakeoff/screenshots/`):

- `linux-ios-linuxrunner.png` and `linux-ios-linuxrunner-*.png` — LinuxRunner baseline
- `linux-ios-kernarium-shell.png` — gadgets-era Alpine shell
- `linux-ios-kernarium-benches.png` — gadgets benches
- `linux-ios-kernarium-jit-benches.png` — JIT + OpenRC benches (6:46 PM ET)
- `linux-ios-kernarium-jit-slim-benches.png` — JIT + slim init benches (6:48 PM ET). The 402-wide framebuffer wraps openssl tables; the serial log is the source of truth.

## LinuxRunner numbers (Simulator, JIT off)

Boot (from the app's own startup.log, first launch at 5:12:27 PM ET):

- Process start to "boot to task scheduling": 133.6 ms
- Process start to shell scheduled: ~229 ms
- Process start to "terminal frontend loaded": ~3.2 s

`uname`: Linux Peek iPhone 17 4.20.69-linuxkit Block Emulation, aarch64, Alpine 3.24.2.

- `sh` loop 20k: real 1.03 s (host 0.074 s, ~14×)
- `dd` zero→null 32 MiB: 5.96 GB/s (a no-op)
- Write 32 MiB then `sha256sum`: write 523.6 MB/s; hash 1.64 s
- `apk add tree`: 3.08 s; `apk add openssl`: 3.39 s, OpenSSL 3.5.9
- openssl evp 16 KiB: aes-256-cbc 169337 kB/s, sha256 376007 kB/s

## Repo and artifacts

https://github.com/davidgeorgehope/linux-ios-fast (private). Created and pushed from the box's existing `gh` login; the mini's GitHub auth was not changed.

Large artifacts: `gdrive:linux-ios-fast/artifacts/` (see REPRODUCE.md for SHA-256s). The Alpine ext4 on Drive may lag the slim-init inittab; the on-disk image and `scripts/guest-run-benches.sh` are authoritative.

## Recommendation

Do not put anything on the iPhone yet.

In the Simulator, Kernarium with the JIT and a slim init is clearly faster than LinuxRunner on the agreed benches (about 3× the shell loop, 4× sha256sum, 2× apk wall-clock, 4–5× OpenSSL evp) and boots to a payload in about one guest second. That JIT path is a local fork that uses macOS MAP_JIT in the Simulator. On a real iPhone, without StikDebug, Kernarium stays on the gadget engine (the ~1.3× column). A device build still needs signing, official iphoneos packaging (KosmicKrisp / Metal 4), a check of the 16 KiB UML window, and David's agreement before any install.
