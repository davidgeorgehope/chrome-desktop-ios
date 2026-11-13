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

A light Alpine XFCE desktop was added after those CPU benches (8:11–8:25 PM ET). See the Desktop section below.

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


## Desktop (Alpine XFCE on the iPad Simulator)

Date: Thu Nov 12, 2026, 8:13–8:25 PM ET. Same JIT-enabled Kernarium build, now also honoring `KERNARIUM_DISPLAY_WIDTH`/`HEIGHT`. Official KDE erofs (~3.8 GB) is unpublished, so this uses a grown Alpine 3.24.2 ext4 instead of waiting on it.

Guest: Alpine 3.24.2, Linux 6.18.60-gf89b4c310c47, XFCE 4.20 on Xorg modesetting, Firefox 151, pcmanfm, xfce4-terminal, mesa-demos, weston/labwc installed as fallbacks. 4 GiB ext4 (~1.3 GiB used). JIT on, 4096 MiB guest RAM, 8 vCPUs. Surface requested 1920×1080 at 160 DPI (`SIMCTL_CHILD_KERNARIUM_DISPLAY_*`). Host: iPad (A16) Simulator, UDID `6532E3AA-A7DF-48F4-9E87-6C4EA94F4C74`, portrait 1640×2360 screenshot (the 16:9 guest is scaled into the view).

Init is still slim (no OpenRC): mount, DHCP, then `start-desktop.sh` (udev, dbus, `/dev/pts`, XFCE). Scripts are in `scripts/desktop-guest/`.

### Measurements (third boot, PTY fix in, 8:24–8:25 PM ET)

Log: `notes/kernarium-desktop-launch3.log` on the mini. Host launch 8:24:23–8:24:24 PM ET.

| Event | Guest uptime | Wall (ET) |
| --- | --- | --- |
| App launch / JIT prepare | — | 8:24:24 PM |
| `DESKTOP_START` (udev + X about to start) | **1.73 s** | 8:24:27 PM |
| `DESKTOP_READY` (XFCE autostart hook; includes a 2 s sleep) | **30.88 s** | 8:24:56 PM |
| Boot to a painted desktop | ~31 s guest / **~32 s** after `simctl launch` | first painted frame was ~20–30 s in earlier boots |
| glxgears (after JIT warmup) | 35.4–51.5 s | **36.8 FPS** (first 7.3 s was 0.27 FPS warmup: 2 frames). Earlier boot: 35.1 FPS |
| `xfce4-terminal` first window | started 51.5 s, present at 54.6 s | window with a root shell (`/ #`) in ~3 s once `/dev/pts` was mounted |
| Firefox 151 `about:blank` | started 54.7 s; still no window at 74.8 s | no visible window in a 20 s budget; the dock launcher is present |

OpenGL: guest **llvmpipe** (Mesa 26.1.6, LLVM 22.1.3, OpenGL 4.6). Host virtio-gpu advertises `+virgl`, `/dev/dri/card0` and `fb0: virtio_gpudrmfb` exist, and `virtio_gpu_dri.so` is installed, but Mesa still reports llvmpipe (`virtio_gpu: driver missing` during X start). So 3D is software in the guest, under the ARM64 JIT, then the host compositor readback. That is the next obvious desktop speed target; it was not fixed in this pass.

Input: Kernarium already exposes `Kernarium Touchscreen` and `Kernarium Keyboard`. The pointer and the on-screen Simulator keyboard chrome are visible in the screenshots. A first-boot terminal failed with `Failed to open PTY`; mounting `devpts` on `/dev/pts` in `start-desktop.sh` / fstab fixed it (see the later screenshots).

Feel: XFCE reaches a usable desktop in about half a minute. The shell and panel are fine for looking around. glxgears holds mid-30s FPS at the 1920×1080 guest surface after warmup — watchable, not snappy, which matches guest llvmpipe. Firefox is installed but did not paint a window in 20 s, so it is not yet a comfortable browser.

LinuxRunner VIRGL/ANGLE desktop was not compared in this pass (the XFCE path on Kernarium was the goal).

Screenshots and video (box `/workspace/`, also `~/linux-ios-bakeoff/screenshots/` on the mini):

- `linux-ios-kernarium-desktop.png` — first painted XFCE desktop (8:17 PM ET)
- `linux-ios-kernarium-desktop-apps.png` — terminal open before the PTY fix (error dialog)
- `linux-ios-kernarium-desktop-terminal.png` — working root shell in xfce4-terminal (8:25 PM ET)
- `linux-ios-kernarium-desktop-boot.mp4` — 44 s, 1640×2360 h264, first boot to desktop (iPad LCD)

## Desktop speed: guest virgl + native-window munmap fix

Date: Thu Nov 12, 2026, 8:31–9:04 PM ET. Same iPad (A16) Simulator UDID, JIT, 1920×1080, 4096 MiB, 8 vCPUs. Guest kernel after the fix: `6.18.60-g8246678b2d74`. Host still uses the Simulator software Virgl path (llvmpipe); KosmicKrisp/Metal 4 cannot run in the iOS Simulator because the iPhoneSimulator 26.5 SDK ships only stub MTL4 headers (`newMTL4CommandQueue` does not compile). An ios-device KosmicKrisp prefix was built and verified at 8:39 PM ET and is not installed on a phone.

### Why guest GL was llvmpipe

Alpine 3.24 `mesa-dri-gallium` 26.1.6 did not contain the virgl gallium driver (`virtio_gpu: driver missing` is Mesa's pipe-loader template, not a missing symlink). `renderD128` and `+virgl` were already present. Mesa 26.1.6 was rebuilt in the Lima musl chroot with `-Dgallium-drivers=virgl,zink,llvmpipe,softpipe -Dvulkan-drivers=virtio,swrast` and installed into the desktop ext4. After that, glxinfo reports `virgl (LLVMPIPE (LLVM 22.1.8, 128 bits))` — guest virgl, host software rasterizer (native ARM, not JIT). Venus is not offered on the Simulator (`UML_GPU_VENUS_OFFERED` is off when `UML_GPU_SOFTWARE_RENDERER` is set for `ios-simulator`).

The image also gained Falkon, xdotool, vulkan-tools, fontconfig, compositor-off xfwm, and a faster `desktop-ready.sh` (no 2 s sleep; Firefox then Falkon).

### Firefox munmap panic

The first post-Mesa boot (host launch 8:42:57 PM ET) reached XFCE and mapped a Firefox window at 1 s, then panicked at guest uptime 138 s:

`Darwin: unable to invalidate guest mm 449 range 0xf7ffff000-0x398f801000` in `darwin_tlb_flush_range` (Firefox DOM Worker, `sys_munmap`).

Cause: the host reserves a 16 KiB-aligned native window ending at `0xf80000000` (62 GiB). A 4 KiB-aligned `start+length` published `uml_darwin_native_end = 0xf7ffff000`, one guest page short. A user munmap split at the kernel end still overlapped the host window; `darwin_uml_vm_unmap_generation` returned EINVAL and `darwin_tlb_invalidate_range` panicked.

Fix (kernel topic, also `patches/0003-um-darwin-align-native-window-end-to-the-host-page.patch`): align `uml_darwin_native_end` up to the 16 KiB host page. Boot now logs `Darwin native window 0xd3fff4000-0xf80000000 (host-page aligned)`. Artifact: `mainline-6.18-arm64-4k-20261112-6.18.60-local2` (`patches/accepted-4k.env.local2`, final tree `9ae1a0b0ef88af94c633b1971bc15cf6083a3d73`).

### Measurements

| Event | Before (8:24–8:25 PM ET) | Virgl guest, old kernel (8:42–8:43 PM) | After native-end fix (9:00–9:04 PM ET) |
| --- | --- | --- | --- |
| DESKTOP_START | 1.73 s | 2.01 s | **1.74 s** |
| DESKTOP_READY | 30.88 s (includes 2 s sleep) | 29.80 s | **28.60 s** |
| Renderer | guest llvmpipe (Mesa 26.1.6, LLVM 22.1.3) | `virgl (LLVMPIPE (LLVM 22.1.8, 128 bits))`; host "Virgl software rasterizer provider: software" | same virgl → host llvmpipe |
| glxgears | 36.8 FPS after warmup (0.27 FPS first 7.3 s) | 26.9–27.9 FPS steady, no 0.27 warmup | **27.4–28.0 FPS** steady |
| xfce4-terminal | ~3 s | visible at TERM_AFTER_3S | visible at 3 s |
| Firefox 151 | no window in 20 s | window at 1 s, kernel panic at 138 s before a painted page | window at 1 s; **example.com fully painted**; still running at 4m09s+ with no panic |
| vkcube | not run | guest swrast/llvmpipe segfault (no Venus on Simulator) | same |

glxgears is slightly lower than guest-llvmpipe-under-JIT because virgl goes through the protocol and a surfaceless host readback. Warmup is gone, 2D/Firefox is actually usable, and the desktop stays up. vkcube cannot use virtio-vulkan here because the Simulator host does not offer Venus.

Screenshots and video (box `/workspace/`, also `~/linux-ios-bakeoff/screenshots/` / `notes/` on the mini):

- `kernarium-desktop-virgl-use.mp4` — first virgl boot, then panic to the home screen
- `kernarium-desktop-virgl-firefox.png` — terminal only, pre-panic
- `kernarium-desktop-native-end-use.mp4` — boot through painted Firefox (9:00–9:04 PM ET)
- `kernarium-desktop-native-end-firefox.png` — example.com at 9:04 PM ET
- `kernarium-desktop-native-end.log` — serial log with renderer strings and the aligned native window

Feel: the shell and panel were already fine; Firefox now paints a real page and the guest no longer dies under a DOM Worker munmap. 3D in the Simulator is still host llvmpipe (~28 FPS gears). Real Metal is on the native macOS `uml-darwin` CLI (next section); Designed-for-iPad is blocked on this Mac by an Xcode/host OS mismatch.

## Real Metal on the Mac (uml-darwin + KosmicKrisp)

Date: Thu Nov 12, 2026, 9:19–9:58 PM ET (America/New_York). Host: Mac mini, Apple M2 Pro (10 cores, 16 GB, 16 KiB pages, display left at 3840×2160). Guest: same Alpine XFCE ext4 and kernel `6.18.60-g8246678b2d74` (local2), `mem=4G`, `ncpus=8`, JIT, virtio-gpu 1920×1080.

### Why not Designed for iPad / Catalyst

The official Kernarium path is `scripts/run-ios-mac.sh` (destination `platform=macOS,variant=Designed for iPad`, cmake preset `kernarium-ios-device`, team `4P2629648N`). Xcode 26.6 / iOS 26.5 SDK refuses that destination: "Xcode doesn’t support My Mac’s macOS 26.3.1 (25D2128)." Available destinations include the paired phones (Silver, Yellow); those were not used. macOS was not upgraded. Catalyst would need macabi slices of KosmicKrisp, which the official prefix does not publish. A minos 27.0 hello-world does run on 26.3.1, so the framework minos is not the blocker — Xcode's Designed-for-iPad destination is.

Device-side work that did land, uninstalled: ios-device runtime with `UML_IOS_DEBUGGER_JIT=OFF` and `UML_GPU_SOFTWARE_RENDERER=FALSE`, packaged Linux-only XCFrameworks (the official `--runtimes all` packager wants a missing Android kernel artifact), MAP_JIT publication for iphoneos / Designed for iPad (`patches/0004-map-jit-designed-for-ipad.patch`), entitlements already contain `com.apple.security.cs.allow-jit`. A pending Keychain prompt on the mini is *not* this build: it is "xcodebuild wants to use your confidential information stored in github.com" and was left untouched.

### Official macOS CLI path (what actually ran)

`dependencies/build-apple-gpu.sh --platform macos` published KosmicKrisp / MesaEGL / MesaGallium under `.build/dependencies/apple-gpu-vulkan-experiment/macos-arm64/` (minos 27.0, sdk 26.5). cmake `--preset macos-integration` produced `.build/presets/macos-integration/bin/uml-darwin`. Default CLI display is VNC (`127.0.0.1:5900`); `--gpu-display=native` is required for an AppKit window (see `scripts/macos-metal/`). Launch used `--execution-engine=jit --gpu-width=1920 --gpu-height=1080`, `--guest-file` for `/boot.env` and the Zink-first session scripts, `mem=4G ncpus=8`, ext4 root. The `init=/uml-per-run-initramfs-did-not-run` token on the kernel command line is the official canary; a 1.4 MiB per-run initrd was written and loaded (`Freeing initrd memory: 1376K`). Host log:

- `Virgl Zink/KosmicKrisp provider: hardware`
- `VNC display: 127.0.0.1:5900 (1920x1080)` and later `VNC display: asynchronous native Metal readback`
- `UML: reserved native kernel window 0x600000000000-0x60024000c000 (… host page 16384)` / `Darwin native window … (host-page aligned)`
- virtio-gpu cap sets 1, 2, and **4 (Venus)**
- 8 vCPUs, kernel `6.18.60-g8246678b2d74`

### Renderer strings (guest, 9:46–9:50 PM ET)

Default GLX (no loader override), i.e. guest virgl → host Virglrenderer → Zink → KosmicKrisp → Apple GPU:

- `OpenGL renderer string: virgl (zink Vulkan 1.4(Apple M2 Pro (MESA KOSMICKRISP)))`
- `OpenGL version string: 4.6 (Compatibility Profile) Mesa 26.1.6`

Guest Zink over Venus ( `MESA_LOADER_DRIVER_OVERRIDE=zink` ):

- `OpenGL renderer string: zink Vulkan 1.4 (Virtio-GPU Venus (Apple M2 Pro) (MESA KOSMICKRISP))`

`vulkaninfo --summary`:

- `deviceName = Virtio-GPU Venus (Apple M2 Pro)`, `deviceType = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU`, `driverName = venus`, `driverInfo = Mesa 26.1.6`, `vendorID = 0x106b`
- also a CPU device: `llvmpipe (LLVM 22.1.3, 128 bits)`

`vkcube` selected `GPU 0: Virtio-GPU Venus (Apple M2 Pro), type: IntegratedGpu`, WSI `xcb`. The visible `Vkcube X11` window stayed black in this session (stderr showed MESA errors); FPS for vkcube was not captured.

### Measurements

| Event | Simulator virgl → host llvmpipe (9:00–9:04 PM ET) | macOS uml-darwin → KosmicKrisp (9:42–9:53 PM ET) |
| --- | --- | --- |
| Boot to desktop | DESKTOP_READY **28.60 s** | **DESKTOP_READY 26.73 s** guest uptime (GUI native launch 10:00:52–10:01:19 PM ET; DESKTOP_START 1.38 s). First SSH+VNC boot was only bounded at ≤68 s because serial was block-buffered. |
| GLX renderer | `virgl (LLVMPIPE (LLVM 22.1.8, 128 bits))` | First SSH session, no loader override: `virgl (zink Vulkan 1.4(Apple M2 Pro (MESA KOSMICKRISP)))`. GUI native launch with the payload scripts: **`===RENDERER_PATH=== guest_zink`**, `zink Vulkan 1.4(Virtio-GPU Venus (Apple M2 Pro) (MESA_KOSMICKRISP))` |
| Guest Zink / Venus | not offered | Yes. `vulkaninfo`: `Virtio-GPU Venus (Apple M2 Pro)`, `venus`, `vendorID 0x106b`, `INTEGRATED_GPU` |
| glxgears (default vsync) | **27.4–28.0 FPS** | 20.086 FPS (SSH session, one 5 s sample; vsync / compositor) |
| glxgears (`vblank_mode=0`) | not measured | **91.5 FPS** first 5 s, then **119.6–119.8 FPS** steady (SSH session, default virgl→KosmicKrisp). Scripted `glxgears -info` on the Zink path printed `GL_RENDERER = zink … Apple M2 Pro` but exited in 2.3 s with no “frames in” line |
| xfce4-terminal | visible | visible at TERM_AFTER_3S (51.58 s) |
| Firefox 151 | example.com painted | window at **1 s** (`FIREFOX_WINDOW` 52.79 s); `FIREFOX_SCROLL` 72.42–77.29 s; example.com painted in the SSH session and in the native-window video |
| vkcube | swrast segfault (no Venus) | selects `Virtio-GPU Venus (Apple M2 Pro)`; the `Vkcube X11` window stayed black (12 s timeout). No FPS line |

A first SSH launch used the CLI default `--gpu-display=vnc` (no AppKit window). `Screen Sharing.app` on `vnc://127.0.0.1:5900` failed with "You cannot control your own screen" (it special-cases localhost). RFB recordings from that session are listed below.

A GUI relaunch at 10:00:52 PM ET with `scripts/macos-metal/launch-in-gui.command` (`UML_GPU_DISPLAY=native`, `--gpu-auto-resize=off`, `script(1)` pty) created an AppKit window titled **Darwin UML Virtio-GPU** (CGWindow id 135, 1920×956 at (0, 30) — not a display-resolution change). `screencapture -v -V 35 -l 135` recorded that window.

Screenshots and video (box `/workspace/`, also `~/linux-ios-bakeoff/notes/macos-metal-desktop/` on the mini):

- `kernarium-macos-metal-vnc.png` — XFCE up over VNC, 9:43 PM ET
- `kernarium-macos-metal-vnc-fps3.png` — renderer strings and 20.086 FPS sample, 9:50 PM ET
- `kernarium-macos-metal-glxgears.png` / `kernarium-macos-metal-glxgears-fps.png` — visible gears, 91–120 FPS with `vblank_mode=0`
- `kernarium-macos-metal-vkcube.png` — black Vkcube X11 window over Firefox
- `kernarium-macos-metal-desktop.mp4` — 6.13 s / 8 fps VNC timelapse
- `kernarium-macos-metal-desktop-rt.mp4` — 20.90 s / 10 fps real-time VNC recording
- `kernarium-macos-metal-native-window.png` — AppKit window at 10:01:35 PM ET, vkcube still up
- `kernarium-macos-metal-native-desktop.png` / `kernarium-macos-metal-native-firefox.png` — frames from the official screencapture
- `kernarium-macos-metal-native-window.mov` — 35.01 s `screencapture` of the Mac window (3840×1912 Retina, 12 fps)
- `kernarium-macos-metal-native-session.log` — line-buffered serial with DESKTOP_READY, renderer strings, Firefox scroll

### Housekeeping in this same stretch

`davidgeorgehope/linux-ios-fast` `f76d75b` (NOTES/REPRODUCE, kernel patch series, desktop-ready). Drive `gdrive:linux-ios-fast/artifacts/`: `alpine-3.24.2-desktop.ext4.gz` sha256 `0ecc51926f03b0ae5b0a1ff5fcd339b08d98e9a0a5cc21dfa7117a85b9a18599`, `kernel-mainline-6.18-arm64-4k-20261112-6.18.60-local2.tar.gz` sha256 `dc0431b2b5fda6d0cc79cad88b0b5f0dd24a3aaf04da09b66dbd8db473c72bbb`. `rclone check --checksum --one-way` reported 0 differences.

The mini's `linux-ios-bakeoff/linux-ios-fast` clone had no remotes and was at `2eb3561`. It was fast-forwarded to `f76d75b` from a bundle built on the box (the mini cannot fetch GitHub over HTTPS without auth; the mini's `gh` login was not changed). Push URL on that clone is set to `DISABLED`. A stash of superseded local drafts remains: `stash@{0}: mini-local-before-ff-to-github-main-20261112-215641`. Do not push linux-ios-fast from the mini. The Kernarium tree stays a local fork of `imxieyi/Kernarium` @ `ce0fa86` and is not pushed.

## Phone

Still Simulator only. A physical iPhone does not get this JIT path without StikDebug, still needs signing and official iphoneos / KosmicKrisp packaging, and the 16 KiB UML window check. The desktop image itself should boot, but it will be on the gadget engine and even more GPU-bound until virgl or Metal is actually used. Do not install on the iPhone until David agrees.


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

In the Simulator, Kernarium with the JIT and a slim init is clearly faster than LinuxRunner on the agreed benches (about 3× the shell loop, 4× sha256sum, 2× apk wall-clock, 4–5× OpenSSL evp) and boots to a payload in about one guest second. That JIT path is a local fork that uses macOS MAP_JIT in the Simulator. On a real iPhone, without StikDebug, Kernarium stays on the gadget engine (the ~1.3× column). A device / Designed-for-iPad build still needs a newer Xcode-to-host-OS pairing (or David's agreement to install on a phone), official iphoneos packaging, and a check of MAP_JIT plus the 16 KiB UML window. Real Metal already runs on this Mac through the official `uml-darwin` CLI and KosmicKrisp (see above): guest virgl or Zink/Venus, Apple M2 Pro in the renderer string, ~120 FPS glxgears with vsync off. Do not install on the iPhone until David agrees.

## JIT near-pass-through (uml-darwin, 12 Nov 2026)

Baseline on the official macOS `uml-darwin` JIT, no GPU, `mem=2G` `ncpus=8`, Alpine 3.24.2-minimal, kernel 6.18.60-g8246678b2d74. Guest RAM is the Darwin direct-root window (`direct-root=yes offset=41943040`). Host numbers are from the same M2 Pro at 10:06 PM ET; the guest baseline launched at 10:11:50 PM ET. Full table: `scripts/cpu-benches/RESULTS.md`. Portable pack: `scripts/cpu-benches/`.

Guest `/proc/cpuinfo` already advertises `aes pmull sha1 sha2 sha3 sha512 crc32 atomics` (the virtual CPU copies the JIT's implemented ID_AA64ISAR fields into AT_HWCAP). OpenSSL evp is the fair hardware-crypto comparison; tiny-sha compiled with gcc is the fair software-CPU comparison.

| Bench | Host | Guest JIT | Ratio |
| --- | --- | --- | --- |
| sh loop 20k, dash | 0.03 s (macOS dash) | 0.24 s (Alpine dash) | 8.0× |
| native-loop 200M, gcc -O2 | 0.39 s (gcc-16) | 0.57 s (gcc 15.2) | 1.46× |
| sha256sum 32 MiB | 0.02 s (HW) | 0.38 s (busybox SW) | 19×, unfair |
| openssl evp sha256 16 KiB | 2,585 MB/s (OpenSSL 4.1.0) | 1,691 MB/s (OpenSSL 3.5.9) | 1.53× |
| openssl evp aes-256-cbc 16 KiB | 1,296 MB/s | 860 MB/s | 1.51× |
| compile tiny-sha, gcc -O2 | 0.24 s (gcc-16) | 2.92 s (gcc 15.2) | 12.2× |
| run tiny-sha 3×32 MiB, gcc -O2 | 0.628 s / 152.90 MiB/s | 1.179 s / 81.42 MiB/s | 1.88× |
| apk add offline (tree+openssl+build-base) | n/a | 3.07 s | — |

Five JIT increments were tried after that baseline and all reverted: longer unsigned runs (wash), a generalized `LDP`/signed/pre/post run (SIGILL, then `/init` hang), no-writeback `LDP`+`LDUR` (same hang), non-negative `LDUR` only (wash), and a 1-entry last-page host-delta cache (regression: tiny-sha 81.42 → 78.45 MiB/s). The table above is unchanged. Indirect ICs, a RET stack, cheaper SVC exits, and a correct pair/signed hoist are still open. vkcube-on-Venus/X11 still black, not diagnosed in this stretch.

The slim guest's first apk attempt failed on DNS (`DNS: transient error`); benches now inject `resolv.conf` and an offline `apks.tar` of Alpine 3.24 aarch64 packages fetched on the Mac. That tarball is not in git.

## Exit profile of the shell and gcc compile (12 Nov 2026, 10:49 PM ET)

A default-off `UML_JIT_PROFILE` counter in the uml-darwin JIT (`patches/0005-jit-exit-profile.patch`) recorded isolated `sh` loop and `gcc -O2` tiny-sha compiles, reset after boot / `apk add` and snapshotting at the end of the bench. Full table: `scripts/cpu-benches/RESULTS.md`. Profiles: `scripts/cpu-benches/profiles/`.

The shell at ~10× was 3.26 million translated-block entries in 0.37 s, split 59% `continued` (1.38M of those were selector mismatches on compiled successors, not unlinked or fairness) and 41% indirect-cache misses. SVC and compile were noise (80 syscalls, 16 ms of compile). The compile at ~11.6× had the same exit mix, plus 1.40 s (47% of wall) spent compiling 681k new blocks with zero shared-cache reuse: the shared cache only publishes when two executors are live at once, and it keys entries by guest PC, so `exec` of `cc1`/`as` under ASLR cannot reuse `libc` or the toolchain. SVC is not the top exit on either bench. The profiler is off unless `UML_JIT_PROFILE` is set, and was not used for the performance table.

## Direct links and A64 indirect table (12 Nov 2026, 11:06–11:09 PM ET)

`patches/0006-jit-direct-and-indirect-links.patch`. Chains now enter with a live store publication and a full link selector (unless a reservation is held on a no-store entry), so compiled direct successors actually get jumped to. A `SUBS` fairness check stops the remaining-instruction counter wrapping, which had hung `grep|sort` with RCU stalls once those links started succeeding. A64 `BR`/`BLR`/`RET` also consult an 8192-entry in-JIT hash behind the 2-cell IC. Isolated profiles: `scripts/cpu-benches/profiles/profile-sh_loop-links.txt` and `profile-compile-links.txt`. Full write-up: `scripts/cpu-benches/RESULTS.md`.

The shell dropped from 0.31 s (10.3×) to 0.25–0.26 s (8.3–8.7×) with the profiler off; `run_blocks` fell from 3.26M to 259k, selector mismatches to ~0, and indirect misses from 1.34M to 1,378. The gcc compile went from 2.78 s (11.6×) to 2.90–2.94 s (12.1–12.3×): execution exits fell (5.54M → 1.02M run_blocks, indirect 2.57M → 202k) but 1.31 s (45%) is still cold translation of ~629k new blocks with no shared reuse, so wall time did not improve. A return-address stack and a deeper per-site IC were not added.

## Fair shell and native-loop (12 Nov 2026, 11:14–11:18 PM ET)

Like-for-like dash on both sides is 0.24 s guest vs 0.03 s host (**8.0×**), slightly kinder than the old ash-vs-dash 8.7×. A tight gcc `-O2` 200M increment loop is **1.46×** (0.57 s guest / 0.39 s host gcc-16), in the same band as evp and tiny-sha, so the remaining shell gap is the interpreter, not ordinary integer JIT. Shared-translation publication with one executor and ASLR off did not warm a second compile (3.10 s then 3.04 s; only 58 shared insertions of 1.5M compiles, almost all `!relocatable`) and was not landed. Full write-up: `scripts/cpu-benches/RESULTS.md`. Raw: `scripts/cpu-benches/profiles/fair-timings.txt`.

A design for a fixed-offset guest user memory mapping (and for sharing translations across exec) is in `DESIGN.md`. It is not implemented.

## Shared translations (12 Nov 2026, 11:26–11:42 PM ET)

`patches/0007-jit-shared-translations`. Official table: `scripts/cpu-benches/RESULTS.md`. The shared cache now publishes with one executor, keeps out-of-range link pointers in a relocatable literal island, and gets a real 2 GiB leftover (the old `guest/2` default was eaten by eight 256 MiB L1s). The relocation cap is 64, not 2. With ASLR off, a warm tiny-sha compile is 1.09 s (4.5×) vs 2.92 s before, and compile time itself is ~3 ms; cold is 1.87 s (7.8×). Fair dash is 0.19 s / 6.3× (was 0.24 s / 8.0×); the tight gcc loop is 0.49 s / 1.26× (was 0.57 s / 1.46×). Host `time -l` on a 14.5 s dash loop shows the leftover shell tax is userspace, not UML kernel/page faults. File+offset keys and PC sliding under ASLR were not added.
