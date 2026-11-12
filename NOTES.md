# Linux-in-iOS Simulator bakeoff

Date: Thu Nov 12, 2026, afternoon/evening ET (America/New_York).
Host: mac.lan (Darwin 25.3.0, arm64 T6020). Xcode 26.6, iOS 26.5 Simulator "Peek iPhone 17" (UDID 8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB).
Work dir: ~/linux-ios-bakeoff. Simulator only. Nothing was installed on the iPhone.
Caveat: the Simulator runs guest code on the Mac's Apple Silicon, so absolute numbers are much faster than a phone. Use them for ranking and architecture, not as a promise of device speed.

Security: third-party trees were scanned before building (see notes/security-scan.txt). No exfiltration or surprise persistence turned up. Kernarium network use is documented fetch/provision. LinuxRunner fetches official distro roots. Henge was inspected only, not built.

## Results

| Candidate | Built | Booted to shell | Architecture | Notes |
| --- | --- | --- | --- | --- |
| Kernarium (imxieyi/Kernarium @ ce0fa868, local fork) | Yes | Yes, ~18:30 ET | Native UML Linux 6.18.60-gf89b4c310c47 + Alpine 3.24.2, Mesa llvmpipe in Simulator | Home-built kernel, boot-base, and a small ext4 rootfs. iOS 26.5 shims, 16 KiB page-aligned UML window, no Android runtime in the Simulator embed. Framebuffer (tty0) and software serial (ttyS0). |
| KellyLinux (heyskylo) | No | No | Claimed Kernarium fork | No public source under that name. heyskylo's public "Linux" tree is a Nyxian x86_64 slot ROM using the rish interpreter, not a Kernarium fork. |
| Henge + plain ARM64 Linux (Leviidev/Henge @ e98920ce) | Not attempted | n/a | Custom arm64-to-arm64 JIT of QEMU vmapple (Apple Virtual Mac), AVPBooter/iBoot, Apple PVG graphics | Code and packaging have no Linux/Alpine/Debian/virtio-gpu guest path. Official scripts are `-sdk iphoneos` only. JIT (StikDebug/StikJIT) is required; the Simulator cannot emulate that faithfully. A Linux guest would be a new machine model, not a config switch. |
| LinuxRunner (mxhm11cr/LinuxRunner @ 4a352114) | Yes | Yes | ARM64 userspace interpreter (Asbestos), no Linux kernel, JIT and VIRGL off | Alpine 3.24.2 ARM64 root shell. Baseline. |

## Side-by-side benches (same Simulator, same Alpine 3.24.2)

Kernarium numbers are from the first complete serial capture at 6:34–6:35 PM ET, guest script `/usr/local/bin/run-benches.sh` (see `notes/kernarium-sim-launch-4.log`). A second run at 6:37 PM ET was consistent (write ~1.8 GB/s, OpenSSL SHA-256 ~591 MB/s at 16 KiB). LinuxRunner numbers are from 5:12–5:26 PM ET the same day.

| Bench | LinuxRunner | Kernarium | Ratio (LR / Kernarium, or as noted) |
| --- | --- | --- | --- |
| Boot to a usable shell (wall clock, includes app start) | ~3.2 s to "terminal frontend loaded" (shell itself scheduled at ~229 ms) | ~7 s to autologin prompt on a clean boot; kernel + rootfs mounted at ~0.47–0.53 s guest time; OpenRC + DHCP then login; auto-benches started at guest uptime 4.86 s | LinuxRunner reaches a terminal faster. Kernarium shows a real kernel on the framebuffer well under a second, then OpenRC. |
| `uname` | `4.20.69-linuxkit Block Emulation` | `6.18.60-gf89b4c310c47` aarch64, SMP | Real Linux kernel vs userspace interpreter |
| `sh` loop, 20,000 increments | real 1.03 s (host 0.074 s, ~14×) | real 0.79 s, user 0.79 s | Kernarium ~1.30× faster |
| `dd if=/dev/zero of=/dev/null bs=1M count=32` | 0.005 s, 5.96 GB/s (a no-op; not a disk test) | 0.0046 s, 6.8 GB/s (32 MiB actually copied) | Similar wall time; Kernarium is doing real work |
| Write 32 MiB (`dd` to a file) | 523.6 MB/s | 1.7 GB/s (0.0186 s) | Kernarium ~3.2× faster |
| `sha256sum` of that 32 MiB | real 1.64 s (~19.5 MB/s); host 0.139 s | real 1.45 s, user 1.44 s (~22.1 MB/s) | Kernarium ~1.13× faster |
| `apk add --no-cache tree` | real 3.08 s, tree 2.3.2 | real 2.35 s, tree 2.3.2, exit 0 | Kernarium ~1.31× faster |
| `apk add --no-cache openssl` | real 3.39 s, OpenSSL 3.5.9 | real 2.51 s, OpenSSL 3.5.9, exit 0 | Kernarium ~1.35× faster |
| `openssl speed -seconds 3 -evp` at 16 KiB | aes-256-cbc 169.3 MB/s; sha256 376.0 MB/s (host OpenSSL 4.1.0: 1294 / 2573 MB/s) | aes-256-cbc 164.0 MB/s; sha256 594.9 MB/s | AES is a tie (Kernarium ~3% slower). SHA-256 is Kernarium ~1.58× faster |

No light desktop was started in this image (minimal Alpine, OpenRC, no APK desktop/WM). The framebuffer is the kernel console + getty, not X/Wayland.

Screenshots (mini: `~/linux-ios-bakeoff/screenshots/`; box copies under `/workspace/`):

- `linux-ios-linuxrunner.png` and `linux-ios-linuxrunner-*.png` — LinuxRunner baseline
- `linux-ios-kernarium-launch.png` — first launch (before the window fix)
- `linux-ios-kernarium-shell.png` — Alpine root shell on tty0 after the window and inittab fixes (`kernarium-04-shell.png`, ~6:30 PM ET)
- `linux-ios-kernarium-benches.png` — auto-bench summary on the framebuffer (`kernarium-06-benches-summary.png`, 6:37 PM ET). The 402-wide console wraps openssl tables; the serial log is the source of truth for the table above.

## LinuxRunner numbers (Simulator, JIT off)

Boot (from the app's own startup.log, first launch at 5:12:27 PM ET, dataless rootfs materialization):

- Process start to "boot to task scheduling": 133.6 ms
- Process start to shell scheduled (`/bin/login -f root`): ~229 ms
- Process start to "terminal frontend loaded": ~3.2 s
- The app lands on Home; Terminal is a tap. A busybox init child logged FAULT/exit 65280 (`_Exit`) and did not stop the shell.

Guest identity:

- `uname`: Linux Peek iPhone 17 4.20.69-linuxkit Block Emulation, aarch64
- Alpine 3.24.2, guest clock UTC

Benches typed into the live shell (host-dropped files are invisible; fakefs uses meta.db):

- `sh` loop, 20,000 increments: real 1.03 s, user 1.00 s, sys 0.02 s
  - Same loop on the Mac host: 0.074 s (~14x faster than the guest)
- `dd if=/dev/zero of=/dev/null bs=1M count=32`: 0.005 s, 5.96 GB/s (a no-op; not a disk test)
- Write 32 MiB then `sha256sum`: write 523.6 MB/s; hash real 1.64 s (~19.5 MB/s)
  - Host `shasum -a 256` of the same 32 MiB: 0.139 s (~11.8x faster)
- `apk add --no-cache tree`: real 3.08 s, user 2.08 s, exit 0, tree 2.3.2, 8502 KiB in 17 packages
- `apk add --no-cache openssl`: real 3.39 s, user 2.32 s, exit 0, OpenSSL 3.5.9, 9303 KiB in 18 packages
- `openssl speed -seconds 3 -evp sha256 aes-256-cbc` (kB/s, 16 KiB blocks):
  - Guest: aes-256-cbc 169337, sha256 376007
  - Host OpenSSL 4.1.0 (not the same version): aes-256-cbc 1324961, sha256 2634828
  - Roughly 7–8x slower in the guest than native on the same Mac

No desktop was started (LinuxRunner's Home can show a Desktop tile, but this run used the Terminal). sysbench was not in the image until we would have added it; openssl covered the CPU case.

## Kernarium: what was built

Upstream at `ce0fa868` does not publish the Linux kernel bundle, boot-base, or a small desktop image (the hashed KDE erofs is ~3.8 GiB). This local fork built those artifacts on the mini and a Lima Ubuntu 24.04 aarch64 VM (`kernarium-linux`), then pointed the verifier at the home-built hashes.

- Case-sensitive volume: `~/linux-ios-bakeoff/KernariumCS.sparseimage` attached as `/Volumes/KernariumCS` (`/dev/disk36s1`).
- Kernel: mainline 6.18, release `6.18.60-gf89b4c310c47`, ABI 26, fingerprint `0x1d7ce579d497fc37`, local id `20261112-6.18.60-local1`. Artifact must be a real directory, not a symlink. vmlinux is 36,479,936 bytes.
- Boot-base: `uml-boot-base-aarch64.cpio.gz` size 1398356, sha256 `4160fae8bd7f98517767c35d6bbaa3818e6711bd96cf9e8c6b387e2a21e5360b`, release `starter-20261112-boot-base-local1`. Env strings in `accepted-aarch64.env` must be single-quoted; SIZE unquoted.
- Rootfs: Alpine 3.24.2 minimal, extracted GPT partition to `alpine-3.24.2-minimal.ext4` (115,687,424 bytes). Inittab runs OpenRC, then `/usr/local/bin/run-benches.sh`, and later autologin gettys on ttyS0 and tty0. This UML build has no `/dev/hvc0`.
- iOS 26.5 shims: AVAudio, BackgroundTasks, PiP, GuestHostCore platform, deployment target 27.0 → 26.5. Simulator packaging omits KRuntime_Android and KosmicKrisp. Ghostty SPM binary zip is vendored locally (do not commit the 73 MiB xcframework).
- UML native kernel window: Simulator host pages are 16 KiB. The reservation hint must be host-page-aligned or mmap falls back below the link address and the guest exits -4. After the fix: reserved `0xd3fff4000-0xf80000000`.

Default guest: `mem=4096M ncpus=8`, display 402×778 at 160 DPI, software Virgl/llvmpipe. `isiOSAppOnMac` is false in the Simulator.

## Reproduce LinuxRunner in the same Simulator

```sh
export PATH="/opt/homebrew/opt/lld/bin:/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/linux-ios-bakeoff/src/LinuxRunner
xcodebuild -project iSH.xcodeproj -scheme LinuxRunner -configuration Release \
  -destination 'platform=iOS Simulator,id=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB' \
  -derivedDataPath ~/linux-ios-bakeoff/src/LinuxRunner/build/sim-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 ROOT_BUNDLE_IDENTIFIER=dev.linuxrunner.app \
  LINUXRUNNER_JIT=NO LINUXRUNNER_VIRGL=NO EXCLUDED_ARCHS=x86_64 build
# Install and launch the copied bundle:
#   ~/linux-ios-bakeoff/bundles/LinuxRunner.app
xcrun simctl install 8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB \
  ~/linux-ios-bakeoff/bundles/LinuxRunner.app
xcrun simctl launch 8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB dev.linuxrunner.app
```

Open Terminal in the app. To type from the Mac: Simulator menu "Send Keyboard Input to Device", click the terminal, then keystrokes. Do not drop files into the host-visible rootfs and expect the guest to see them; fakefs metadata will not list them.

## Reproduce Kernarium

See `linux-ios-fast/REPRODUCE.md` (and `patches/`, `scripts/`) in this work tree. Short path once artifacts exist:

```sh
# App bundle already built:
#   ~/linux-ios-bakeoff/bundles/Kernarium.app
UDID=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB
xcrun simctl install "$UDID" ~/linux-ios-bakeoff/bundles/Kernarium.app
CONTAINER=$(xcrun simctl get_app_container "$UDID" com.imxieyi.Kernarium data)
mkdir -p "$CONTAINER/Documents" "$CONTAINER/tmp"
rm -f "$CONTAINER/tmp/kernarium-overlay.ext4"
ln -sfn /Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4 \
  "$CONTAINER/Documents/alpine-3.24.2-minimal.ext4"
SIMCTL_CHILD_KERNARIUM_ROOTFS=alpine-3.24.2-minimal.ext4 \
  xcrun simctl launch --console-pty "$UDID" com.imxieyi.Kernarium
```

Do not pass both `-scheme` and `-target` to xcodebuild. Rebuild helper: `notes/rebuild-and-relaunch.sh`. Editing the ext4 must be done inside Lima's own disk (copy, e2fsck, loop-mount, copy back, `chmod u+w`); virtiofs of the case-sensitive volume will not allow a writable loop mount.

## Repo and artifacts

The bakeoff notes, reproduce steps, and local-fork patch live in `~/linux-ios-bakeoff/linux-ios-fast`. Large artifacts were uploaded to Google Drive `gdrive:linux-ios-fast/artifacts/` (see that repo's REPRODUCE.md for SHA-256s). The private GitHub repo `davidgeorgehope/linux-ios-fast` could not be created from this machine: GitHub CLI is logged out, SSH keys are rejected, and Cursor's GitHub App cannot see the repo. The local git history is ready to push once David signs `gh` in (do not change auth from an agent session).

## Recommendation

Do not put anything on the iPhone yet.

Kernarium is the one that is actually a Linux kernel in an iOS Simulator app, and once it is up it beats LinuxRunner on the I/O and most CPU benches above. It is not uniformly "much faster": boot to a typed shell is slower (~7 s vs ~3.2 s), and OpenSSL AES-256 is a tie. The architectural gap (native UML vs a userspace interpreter) is the reason to prefer it, especially on a real device where an interpreter would hurt more — but Simulator numbers will not match a phone.

To put this on the phone later, after David agrees: keep or replace the iOS 26.5 shims (device SDK is still 26.5 here; upstream wants iOS 27), run the official device packaging (KosmicKrisp / Metal, Android runtime if you want that guest too), sign with `Signing.local.xcconfig`, and test the 16 KiB window reservation on device. Never install until it works in the Simulator and he agrees.
