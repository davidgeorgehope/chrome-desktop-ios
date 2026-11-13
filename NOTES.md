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

Feel: the shell and panel were already fine; Firefox now paints a real page and the guest no longer dies under a DOM Worker munmap. 3D in the Simulator is still host llvmpipe (~28 FPS gears). Real Metal is on the native macOS `uml-darwin` CLI (next section). The Designed-for-iPad destination is no longer blocked by the host OS (see the 13 Nov 2026 6:01 AM ET upgrade); launching still needs a development signature.

## Real Metal on the Mac (uml-darwin + KosmicKrisp)

Date: Thu Nov 12, 2026, 9:19–9:58 PM ET (America/New_York). Host: Mac mini, Apple M2 Pro (10 cores, 16 GB, 16 KiB pages, display left at 3840×2160). Guest: same Alpine XFCE ext4 and kernel `6.18.60-g8246678b2d74` (local2), `mem=4G`, `ncpus=8`, JIT, virtio-gpu 1920×1080.

### Why not Designed for iPad / Catalyst

As of 13 Nov 2026, 6:37 AM ET, this is historical: the mini is on macOS Tahoe 26.7.3 (25G342) and Xcode 26.6 lists `My Mac` with `variant:Designed for [iPad,iPhone]`. See the upgrade section at the end of this file. Previously, on macOS 26.3.1 (25D2128), Xcode 26.6 / iOS 26.5 SDK refused that destination: "Xcode doesn’t support My Mac’s macOS 26.3.1 (25D2128)." Paired phones (Silver, Yellow) were not used then either. Catalyst would need macabi slices of KosmicKrisp, which the official prefix does not publish. A minos 27.0 hello-world does run on 26.3.1, so the framework minos is not the blocker — Xcode's Designed-for-iPad destination is.

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

## Desktop boot: glycin/bwrap stall (13 Nov 2026, 2:00–2:20 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Host: official 4K `uml-darwin` (`macos-integration`), mem=4G, ncpus=8, guest framebuffer 1920×1080, VNC. Image: `/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop.ext4` (unchanged; sha256 `c7f65c84613ca27f22a634779ecc3b6ae7fac68ff5e367530280e7fac74e73ad`) with session scripts overlaid from `scripts/desktop-guest/`.

The old ~26.8 s `DESKTOP_READY` (and the Simulator 28.6 s llvmpipe result) was not an fc-cache miss, xfconf, or GPU/vblank init. Fontconfig and GTK icon caches were already in the image (a forced `fc-cache -f` was 2.74 s; icon caches 1.07 s). gdb `thread apply all bt` plus `/proc/<pid>/task/*/wchan` showed xfwm4's main thread blocked in `libglycin-2.so.0` and a `gly-hdl-loader` thread in `do_wait`, with a child `bwrap --unshare-all` hung in UML namespaces. Isolating `xfwm4 --compositor=off --vblank=off` with warm caches still took ~10 s until `_NET_SUPPORTING_WM_CHECK` appeared, for the same reason.

Fixes in `scripts/desktop-guest/start-desktop.sh`: replace `/usr/bin/bwrap` with a POSIX passthrough (original saved as `bwrap.real`); hide `/usr/share/glycin-loaders` only until the WM is up, then restore it; start XFCE sessionless (`xfconfd`, then `xfwm4 --compositor=off --vblank=off --sm-client-disable`, then settings/panel/desktop) so xfce4-session's SM timeouts are skipped; disable at-spi, gnome-keyring and xfce4-power-manager autostarts. Do not remove libglycin or stub the loaders (those added GTK pixbuf timeouts and pushed READY to ~44 s). `desktop-ready.sh` now hard-kills a hung vkcube (the known black window) so it cannot block Firefox, and detects the Firefox window with `xdotool` / `xlsclients` / `_NET_CLIENT_LIST_NAMES` because `xwininfo` is not in the image.

| variant | DESKTOP_READY | notes |
| --- | ---: | --- |
| original startxfce4 (GPU / Zink, prior) | 26.7–26.8 s | two ~10 s SM/glycin gaps |
| caches pre-warmed, isolated xfwm4, compositor/vblank off | WM at 17.75 s | fc-cache was not the stall; xfwm still ~10 s |
| bwrap passthrough + sessionless (glycin still on the WM path) | 11.88 s | XFWM_START 2.83, XFWM_READY 11.84 |
| hideconf + passthrough + sessionless (GPU / Zink) | **8.68 / 8.71 / 8.75 s** | panel process at 9.0 s; production script 8.75 s |
| same hideconf path on llvmpipe | **7.42 s** | same class of stall, not GPU-specific |
| production script, then desktop-ready hook (GPU / Zink) | READY 8.75 s | guest_zink; Firefox window 1 s after launch (uptime 42.80 s, after gears + a vkcube timeout + terminal) |

A lighter openbox/labwc image was not needed. The official launch overlay and a new Drive image (`alpine-3.24.2-desktop-fast.ext4.gz`, uncompressed sha256 `bc60fbe9a0cfa0290328775ccd97a00ed6741dbb5c114003ca49748e230c0063`, gz sha256 `721b2c12359178511e9741846385155c9f2847d86c978bae1a6bf30c02c6f6d8`, 994,836,889 bytes) carry the fast path. The previous desktop image and `alpine-3.24.2-desktop.ext4.gz` were kept.


## Desktop boot timeline and labwc (13 Nov 2026, 2:27–2:41 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 4K `uml-darwin`, mem=4G, ncpus=8, 1920×1080 VNC. The 8.75 s XFCE `DESKTOP_READY` from the previous pass was broken down with timestamped guest stages and 0.2 s `/proc` sampling of xfwm4.

Timeline of the 8.75 s XFCE path (clean production boot in parentheses; a sampled boot is noted where it inflated the wait):

| stage | guest uptime | delta |
| --- | ---: | ---: |
| kernel start | 0.00 s | |
| `Run /init` (initramfs) | 0.25 s | 0.25 s |
| `start-desktop.sh` begins | 0.71–0.87 s | ~0.5 s slim init / switch_root |
| udev + dbus + `/dev/dri` | 1.09–1.38 s | ~0.4 s (OpenRC is not used; udev settle is ~0.2 s) |
| Xorg actually accepts connections | 2.68 s (startx was 3.10 s to the first client) | 1.4–1.8 s |
| xfwm4 advertised `_NET_SUPPORTING_WM_CHECK` | 8.58–8.75 s | **5.5–5.9 s** |

The 5.9 s window-manager wait is the remaining XFCE cost. Samples showed xfwm4 cpu-bound (`utime` climbed the whole interval): first `folio_wait_bit_common` (text-page I/O), then **`drm_version`**, a `[pango] fontcon` thread on `futex`, a Mesa `disk$0` shader-cache thread, and later `gly-global-exec` even with glycin-loaders hidden. `xfwm4 --compositor=off --vblank=off` still opens DRM/Mesa. LIBGL_ALWAYS_SOFTWARE / llvmpipe on xfwm4 only did not help (it still JITs Mesa). Early raw Xorg (skipping startx) moved XFWM_START from 3.10 s to 2.72 s and READY only from 8.75 s to 8.63 s. Preloading GTK/xfwm into the page cache during X start did not cut the JIT. The initramfs is already 1388 KiB (freed at 0.23 s). There is no cross-boot persistent JIT translation cache today; a file-backed shared cache would be the lever for a *warm* XFCE boot, but it is not implemented.

labwc (already in the image) reaches a Wayland socket in ~1.3 s after dri is ready:

| variant | DESKTOP_READY | Firefox |
| --- | ---: | --- |
| XFCE sessionless, production (before this pass) | 8.75 s | window 1 s after launch, but official desktop-ready ran vulkan/gears/vkcube first, so the window was at 42.8 s uptime (~34 s after READY) |
| XFCE + early Xorg, xprop wait | 8.63 s | window **2.8–3.0 s after READY** when Firefox starts immediately |
| **labwc (Wayland, three boots)** | **2.40 / 2.56 / 2.61 s** | window visible on VNC by ~3 s after READY; example.com painted by ~12 s after READY (early VNC still showed “Waiting for example.com…”) |

A lighter stack was enough: no need to wait out xfwm's GTK/Mesa JIT. `scripts/desktop-guest/start-desktop-labwc.sh` is the default for `scripts/macos-metal/launch-uml-darwin-desktop.sh`; `UML_DESKTOP=xfce` selects the sessionless XFCE path (which now also starts Firefox immediately at READY). XFCE `desktop-ready.sh` skips a second Firefox if one is already running, and otherwise launches it before vulkaninfo/gears/vkcube.

New Drive image, older ones kept: `alpine-3.24.2-desktop-labwc.ext4.gz` (994,819,499 bytes, sha256 `9471344de45d308d2f4bb4db20b076be906d431ba935f15f2d56e00d21901480`; uncompressed sha256 `0564698ccf4064b975e7998a471295d279d9b3542f2b95802c54aad41e5fdab3`). It bakes labwc as `/usr/local/bin/start-desktop.sh` and keeps the XFCE script as `start-desktop-xfce.sh`.

## labwc renderer and Firefox time-to-page (13 Nov 2026, 2:47–3:15 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 4K `uml-darwin`, mem=4G, ncpus=8, 1920×1080 VNC. Image still `alpine-3.24.2-desktop.ext4` / the labwc-baked copy; no new Drive upload (Firefox time-to-page did not improve by 2×).

### Renderer

labwc is on **real Metal**, but the guest path is **wlroots GLES2/EGL**, not pixman and not in-guest Venus. labwc `-d` logs `render/egl.c`: EGL 1.5, vendor Mesa Project, EGL driver `virtio_gpu`, device `/dev/dri/card0`. Guest `eglinfo` reports OpenGL ES renderer `virgl (zink Vulkan 1.4(Apple M2 Pro (MESA_KOSMICKRISP)))`. The host log says `Virgl Zink/KosmicKrisp provider: hardware`. `vulkaninfo` also offers `Virtio-GPU Venus (Apple M2 Pro)` and llvmpipe; the compositor is not using those directly. `WLR_RENDERER` was left at the wlroots default (gles2). `WLR_RENDERER=vulkan` (in-guest Venus) was not needed and was not landed.

Windowed Firefox 151.0.3 `about:support` (kiosk, `layout.css.devPixelsPerPx=0.38` so the Graphics table fit on a 1080p VNC shot) agrees: compositing is **WebRender**, EGL vendor **Mesa Project**, EGL 1.5, OpenGL ES 3.2 Mesa, GPU #1 renderer **`Mesa -- virgl (zink Vulkan 1.4 (Apple M2 Pro MESA_KOSMICKRISP))`**. Same guest-virgl → host-zink/KosmicKrisp Metal path as labwc, not software WebRender and not llvmpipe. Features also showed `GPU process: false`.

glmark2 is not in the image. `es2gears_wayland` printed `EGL_VERSION = 1.5` and then segfaulted in `libwayland-client`. `vkgears` failed with `wl_seat.get_keyboard called when no keyboard capability has existed` (libdecor-cairo also failed to init). There is no virtio-input / evdev keyboard or pointer in the guest, so the wlroots seat has no keyboard capability. A VNC smoke test moved the host-side cursor to the click coordinates, but clicks and keypresses did not change the Firefox UI — the `--gpu-display=vnc` server is a framebuffer view and is not wired to a guest input device.

### Firefox timing

The ~12 s from READY to a painted example.com is **engine time, not network**. DNS was 0.09 s; `wget` of example.com was 0.63 s (577 bytes). A self-contained `file://` page (`LOCAL_PAINT_OK`, solid green) painted at **10–12 s after READY**, as soon as the `file:// Content` process appeared (~12.5 s). Breakdown of a typical cold start with the pre-created profile:

| phase | after READY |
| --- | ---: |
| `FIREFOX_START` | 0.02–0.03 s |
| parent only (libxul I/O + uml-darwin JIT) | until ~4.5–5.1 s |
| first child (Socket Process / forkserver) | ~4.5–5.1 s |
| RDD | ~7.7–8.5 s |
| Web Content (brief) | ~10.0–11.0 s |
| `file://` / Isolated Web Content | ~11–13 s |
| window chrome | ~6 s (VNC) |
| local page or first example.com text | ~10–12 s |
| example.com fully painted (icon + translations) | ~12 s (baseline, sandbox on) |

Attacks and results:

- **Pre-created profile** (first-run / welcome / telemetry off): the `mozilla.org/privacy/firefox` tab is gone. This is landed. It does not cut the ~12 s engine clock.
- **Content sandbox off** (`MOZ_DISABLE_*_SANDBOX=1`, `security.sandbox.content.level=0`): the Firefox `Chroot Helper` disappears (same class of UML namespace issue as glycin/`bwrap --unshare-all`). Time-to-page does **not** drop. A warning banner appears, and one `https://example.com` load reached English body text at 10 s but stayed on “Transferring data from example.com…” through 20 s (the baseline 94 KiB multilingual + icon paint did not finish). Sandbox-off is **not** the production default.
- **`dom.ipc.processCount=1`**: Isolated Web Content still spawned. **`MOZ_FORCE_DISABLE_E10S`** is ignored on this Firefox 151 release build.
- **Prefault of libxul** during labwc start: finished at ~1.24 s guest uptime (cheap). First child improved by at most ~0.6 s and is not a 2× lever.
- **Same-boot warm start** after a clean `SIGTERM`: the profile was only 1.1 MiB (no `startupCache`). The second Firefox’s content process still appeared at 10.41 s vs 10.45 s cold. The tax is uml-darwin JIT of libxul in each new process, not Firefox’s JS startup cache.
- No new Drive image: time-to-page is still about 12 s, not under 6 s. Older images were kept. `scripts/desktop-guest/start-desktop-labwc.sh` now installs the kernarium profile (and overlays `firefox-kernarium-profile.sh`) and prefaults libxul; the sandbox stays on.

## labwc VNC input (13 Nov 2026, 3:11–3:21 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 4K `uml-darwin`, mem=4G, ncpus=8, 1920×1080 VNC. No new Drive image (this is an overlay-script fix, not a baked image change).

The host VNC path was already wired end-to-end: the display maps keys and the pointer to evdev-like events, the in-process GPU service sends them over a `SOCK_DGRAM` socketpair, the kernel command line carries `uml_vnc_input.fd=8`, and `uml_vnc_input` registers **Darwin UML VNC Keyboard** (`/dev/input/event0`) and **Darwin UML VNC Tablet** (`/dev/input/event1`, `INPUT_PROP_DIRECT` plus `BTN_TOUCH`). Every recent desktop boot already logged `uml_vnc_input: registered keyboard and tablet at fd=8`. Clicks and keys over VNC still did nothing because userspace never opened those devices.

The production default was `WLR_BACKENDS=drm`. In wlroots, naming only `drm` disables the libinput backend, so labwc never created a keyboard or pointer seat. The fix is `WLR_BACKENDS=drm,libinput` (still overridable) plus a best-effort `chmod 666` of the evdev nodes so they are openable as soon as labwc starts, before udev retags them `root:input`. No new virtio-input device or uinput/evdev bridge was needed.

Proof, via `vncdotool` against `127.0.0.1:5900`, with a distinctive local page (`INPUT_HOME`, yellow `CLICK_ME` link, plus `typed.html` / `clicked.html` targets). Screenshots are in `notes/desktop-input-proof/` (copies also under `/Users/davidhope/linux-ios-bakeoff/notes/macos-metal-desktop/`):

- `input-proof-home.png` — Firefox showing `INPUT_HOME` / `file:///tmp/ff-local/index.html`.
- `input-proof-click-hover.png` — pointer over `CLICK_ME`; Firefox status tooltip `file:///tmp/ff-local/clicked.html`.
- `input-proof-link-clicked.png` — green `LINK_CLICKED` page, “The VNC click reached Firefox.”
- `input-proof-typed-urlbar.png` — URL bar contains `file:///tmp/ff-local/typed.html` (typed over VNC; autocomplete open).
- `input-proof-typed-ok.png` — magenta `TYPED_OK` page after Enter, “The VNC keyboard reached the URL bar.”

The same seat unblocks the gears clients that previously failed for lack of a keyboard capability. With `XDG_RUNTIME_DIR=/tmp/runtime-root` (labwc’s runtime dir) and `WAYLAND_DISPLAY=wayland-0`, `es2gears_wayland` printed `EGL_VERSION = 1.5` and stayed alive, and `vkgears` also stayed alive (it previously died with `wl_seat.get_keyboard called when no keyboard capability has existed`).

`FIREFOX_URL` (default `https://example.com`) is now an optional override on the production labwc start script, used by the input-proof overlay.

## Shared translation cache vs a second Firefox content process (13 Nov 2026, 3:21–3:35 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 4K sources, measured on a side `uml-darwin-stats` binary (official `uml-darwin` inode unchanged). mem=4G, ncpus=8, labwc desktop, Firefox 151 loading example.com.

The shared cache is already keyed by file+offset and slides guest PCs, so a second process mapping the same `libxul.so` page should hit. A same-boot warm Firefox after SIGTERM had previously shown no help (content process 10.41 s vs 10.45 s cold). Instrumentation (`UML_JIT_SHARED_STATS=1`, plus guest `/proc` maps) found the following, in this order of the suspected causes:

| candidate | finding |
| --- | --- |
| Cache size / eviction | **The cause.** Default leftover is 3 GiB (`guest/2 + 1 GiB`). It fills at ~1.33M entries mid-Firefox. `reclaim_unused` evicts only `use_count==1` owners, but live L1s pin the entries, so `evictions=0`. New content-process PCs hash to *different shards* (shard key is the ASLR'd guest VA). Further publications are rejected (`rejected` climbed to **698,874**). Those unique blocks are never stored, so a later content process cannot hit them. |
| Reloc cap | Not the cause. `malformed` stayed in the tens to low hundreds. |
| Different mapping slide | File+offset works: `id0=0`, `idN` in the millions. Socket/forkserver/content map libxul at different slides than the parent; `location`/`slide` hits were 100k–300k. |
| Non-relocatable literals | Materialization failures were almost all tiny `mat_arena` (dozens), not link refusals. `reuses` tracked `matches` almost 1:1. |
| W^X / self-modifying invalidation | No version-churn signal in the stamps; identity stayed stable for the backing. |
| Per-mm flush on exec | The process-wide cache is not flushed. The miss is admission rejection, not a drop of already-stored entries. |

Before/after at the default 3 GiB cap, same first-boot workload:

| | insertions (end of first session) | evictions | rejected | first Isolated Web Content after READY |
| --- | ---: | ---: | ---: | ---: |
| Before (reject-on-full) | frozen at 1,331,938 | 0 | 698,874 | ~11–13 s (prior official baseline) |
| After (evict in-use + cross-shard) | continued, 2.0M+ | 757k by warm-restart point | 1–3k | 14.6 s (not a first-load win) |

`--jit-cache-budget=8G` (6 GiB shared at 8 vCPUs) holds one Firefox unique set (~2.41M entries, 5.48 GiB) with **zero evictions and zero rejects** through the first session. First Isolated Web Content was still 16.0 s after READY — the first content process must compile its unique libxul paths once. A same-boot `killall`+restart in that 8G run had not spawned Isolated Web Content by 25 s after the warm start (helpers were also late vs the first session); that is not a demonstrated time-to-page win, and the restart method may have been messy. Persist-to-disk across boots was not landed (not cheap: ~2 GiB payload plus relocations and stamp versions).

The official 4K binary and identity were left alone. The evict-on-full change and the optional stats dump are in `patches/0011-jit-shared-evict-on-full`. The official desktop launcher accepts `UML_JIT_CACHE_BUDGET` (for example `8G`) once a rebuilt uml-darwin is in use.

## Official evict-on-full suite, and packed publication (13 Nov 2026, 3:34–3:55 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 4K identity unchanged (`identity.env` v26, fingerprint `0x1d7ce579d497fc37`). Official `uml-darwin` inode **244909018** (1:09 AM ET, 54280296 bytes) was not overwritten.

### Evict-on-full vs official 4K, same-session official suite

Full official CPU suite (mem=2G, ncpus=8, profilers off, ASLR on, `apks.tar`, minimal ext4). Evict side binary `uml-darwin-stats` inode 244932223. Official rerun immediately after.

| bench | morning official 4K | same-session official 4K | evict-on-full |
| --- | ---: | ---: | ---: |
| dash / ash | 0.18 / 0.18 | 0.19 / 0.18 | 0.18 / 0.18 |
| apk add | 2.80 s | 2.78 s | 2.82 s |
| evp aes-256-cbc 16 KiB | 1,039,985.32k | 1,001,947.14k | 1,004,328.28k |
| evp sha256 16 KiB | 1,790,006.61k | 1,780,831.21k | 1,780,290.90k |
| compile-cold | 2.11 s | 2.00 s | 2.07 s |
| compile-warm | 1.15 s | 1.14 s | 1.17 s |
| tiny-sha | 1.171529 s / 81.94 MiB/s | 1.177390 s / 81.54 MiB/s | 1.189288 s / 80.72 MiB/s |
| tight loop | 0.49 s | 0.49 s | 0.49 s |

tiny-sha digest matched `bcb5fa62…` on all three. The morning AES figure is higher than *both* same-session binaries; evict vs the same-session official rerun is within noise (evict AES is slightly higher). Evict-on-full is a correctness/admission fix, not a suite wall-time win, so the official 4K binary and identity were not promoted.

### Cold-translation SIGPROF (official 4K, 999 Hz)

Guest script: offline `apk add` then one `compile_tiny_sha`. A 1.2 s pause at `COMPILE_COLD_START` let the 1 s SIGPROF flusher snapshot the cumulative histogram; subtracting that from the exit dump isolates the compile window (1632 samples, 2.08 s wall).

| bucket | boot+apk | compile window |
| --- | ---: | ---: |
| JIT generated code | 56.0% | 12.0% (~0.25 s, near the 0.24 s host-native compile) |
| host memmove/memset | 29.0% | 24.8% |
| host malloc | 3.5% | **34.7%** |
| shared-cache find / `valid_shared_translation_shape` | 0.8% | **11.5%** (shape walk 6.0%) |
| decode + emit + `compile_once` | 0.2% | 3.7% |
| link table + icache/W^X + arena | ~0.8% | ~5.6% |
| insert lock | 0.03% | 0.1% |

The 8.6× is not the translator's decoder or emitter. It is publication: four heap allocations and copies per `SharedTranslation`, plus a second shape walk and hash-map growth. Locks and a cheaper first-tier emit are the wrong levers. `maximum_block_instructions` cannot rise above 64 without widening the write mask.

### Packed publication (`patches/0012-jit-publish-alloc`)

A side `uml-darwin-fast` (inode 244934602, 3:49 AM ET) packs guest words, host words, and relocations into one payload, skips the duplicate `insert()` shape check, and pre-sizes the shard and location maps. Official binary left alone.

| | official 4K | packed-publish |
| --- | ---: | ---: |
| compile-cold | 2.06 / 2.07 s | **1.96 / 1.98 s** (~5% ) |
| apk add (same boots) | 2.80 / 2.81 s | 2.81 / 2.81 s |
| Firefox Isolated Web Content after READY | 12.27 s | 11.93 s |

Post-change compile-window SIGPROF: shape walk 6.0% → 0, malloc samples 566 → 466. example.com is still the production `FIREFOX_URL`; Isolated Web Content is the compile-bound content-process signal (light `ps` probe, production labwc start, sandbox on, `WLR_BACKENDS=drm,libinput`). Official identity was not bumped.


## labwc image journal and publish arena (13 Nov 2026, 3:56–4:24 AM ET)

Date: Fri Nov 13, 2026, America/New_York.

### labwc Drive image

The production file `alpine-3.24.2-desktop-labwc.ext4` (and the sibling `alpine-3.24.2-desktop-fast.ext4`) was not failing only because it was mode 0444. Both baked images had a dirty ext4 journal (`INCOMPAT_RECOVER`, incompat 0x2c6). The production overlay mounts the image read-only as `/lower` (`UML_BOOT_UPPER=tmpfs`), so the kernel cannot replay the journal and panics with `EXT4-fs: write access unavailable, cannot proceed` / `UML_BOOT_ERROR:cannot mount /dev/ubda`. The earlier XFCE `alpine-3.24.2-desktop.ext4` is clean (incompat 0x2c2) and already booted at 0444 with `ubd0c`.

Repair: APFS-clone to a writable `*.rw.ext4`, boot official 4K `uml-darwin` once with `UML_BOOT_UPPER=none` (rw mount), remount ro, poweroff. Journal replay completed in ~1.6 s (`EXT4-fs: recovery complete`). Dirty originals were kept as `*.ext4.dirty-journal-20261113`. Clean 0444 clones were installed at the production names.

A production-launcher boot of the clean 0444 labwc image (03:59:57 AM ET, official inode 244909018 unchanged): **DESKTOP_READY at guest uptime 2.94 s**, Firefox started immediately, example.com painted, VNC pointer clicked “Learn more” (navigated to `www.iana.org/help/example-domains`), and the URL bar accepted the typed string `input-ok`. Screenshots: `notes/macos-metal-desktop/labwc-clean-shots/`. `WLR_BACKENDS=drm,libinput` as before.

`scripts/macos-metal/launch-uml-darwin-desktop.sh` now:

- Refuses a dirty-journal image with an explicit message (does not boot into the overlay panic).
- Copies a clean but read-only image to a writable sibling `*.rw.ext4` (`cp -c` APFS clone when possible, otherwise a full copy) and reuses that copy when it is up to date; if the copy cannot be made, it refuses clearly.
- Accepts `UML_ROOTFS` as an override.
- If VNC port 5900 is already in use (macOS Screen Sharing after a reboot holds it on launchd), falls back to `--gpu-vnc-port=5901` and says so. Screen Sharing is not disabled.

Clean labwc image SHA-256 (uncompressed) `02a13eb21a63956f625f1f1789ae979ba0c4fbf2c0010f429ed4c867fe8b0617`. Local gzip `-1` of that image is `alpine-3.24.2-desktop-labwc-clean-20261113.ext4.gz` (1,091,534,974 bytes, sha256 `2a219e5409a7e3a52a197a624d6edd5862270edd95014bc57d241347d208a7eb`). The previous dirty Drive object was kept as `alpine-3.24.2-desktop-labwc-dirty-journal.ext4.gz` (same bytes, sha256 `9471344de45d308d2f4bb4db20b076be906d431ba935f15f2d56e00d21901480`, uncompressed `0564698…`). The already-shared Drive file ID was then updated in place with the clean gzip (see the 4:25 AM ET section below).

The same journal repair was applied to `alpine-3.24.2-desktop-fast.ext4`; its dirty original was also parked.

### Publish arena (`patches/0013-jit-publish-arena`)

A side `uml-darwin-arena` (inode 244936914, 4:06–4:07 AM ET) puts the `SharedTranslation` object and packed payload in one process-wide bump arena of recycled 1 MiB chunks (thread-local bump, bulk free on evict). Official 4K inode 244909018 left alone. Same-session compile-cold / apk add (mem=2G, ncpus=8, profilers off, interleaving official / packed-publish / arena):

| | official 4K | packed-publish | publish-arena |
| --- | ---: | ---: | ---: |
| compile-cold (two runs) | 1.99 / 2.08 s | 1.94 / 1.94 s | **1.91 / 1.94 s** |
| apk add (same boots) | 2.86 / 2.80 s | 2.80 / 2.82 s | 2.80 / 2.83 s |

Firefox Isolated Web Content after READY, same session after the 4:15 AM reboot (production labwc start, light `FF_SNAP` probe, sandbox on, `WLR_BACKENDS=drm,libinput`, VNC on 5901 because Screen Sharing held 5900):

| | official 4K | packed-publish | publish-arena |
| --- | ---: | ---: | ---: |
| DESKTOP_READY | 3.51 s | 2.98 s | 2.98 s |
| Isolated Web Content after READY | 15.68 s | 14.40 s | **14.15 s** |

Those Firefox numbers are slower than the earlier 3:53 AM ET same-machine figures (official 12.27 s, packed 11.93 s) because the session was post-reboot and cold. Within this session, arena is tied with packed-publish on compile-cold and slightly ahead on Isolated Web Content. Evict-on-full plus packed publish plus the arena is a verified compile-cold improvement of about 5–8% versus official 4K, not a clean full-suite wall-time win, so the official identity was **not** bumped (still v26 / `0x1d7ce579d497fc37`). The official binary was kept as the fallback.


## Drive repair, 4:15 AM reboot, and Simulator JIT through a48d90a (13 Nov 2026, 4:25–4:39 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 4K inode still 244909018 (identity v26 / `0x1d7ce579d497fc37`). Screen Sharing was left on port 5900.

### Drive images (in-place update of the already-shared links)

The shared labwc and fast Drive objects were the dirty-journal snapshots and did not boot under the production ro overlay. The dirty payloads were server-side copied to new names, then the original file IDs were overwritten with the journal-replayed gzs so existing links now serve the clean images.

| Object | Drive file ID (unchanged for the names already shared) | gzip SHA-256 | uncompressed SHA-256 |
| --- | --- | --- | --- |
| `alpine-3.24.2-desktop-labwc.ext4.gz` (clean, 1,091,534,974 bytes) | `1z5ekg6nr5qcv86ST-yy_O3ZLk9nIJYvR` | `2a219e5409a7e3a52a197a624d6edd5862270edd95014bc57d241347d208a7eb` | `02a13eb21a63956f625f1f1789ae979ba0c4fbf2c0010f429ed4c867fe8b0617` |
| `alpine-3.24.2-desktop-fast.ext4.gz` (clean, 1,091,530,692 bytes) | `1T6V-9MLZqjtNOYIB5vkJ4FDI6phrYcld` | `e4a1f6858ec238ca313e5abef2de6897e018ae675950e115dff4acbb0b9c1d6b` | `caa0801f2b19c5868afc9cd345b34a6ec0188b69b722d9262f1081923551fd1a` |
| `alpine-3.24.2-desktop-labwc-dirty-journal.ext4.gz` (kept, 994,819,499 bytes) | `1cP4YnylIgWlkcwQ2vS1aaybNpy2THOLq` | `9471344de45d308d2f4bb4db20b076be906d431ba935f15f2d56e00d21901480` | `0564698ccf4064b975e7998a471295d279d9b3542f2b95802c54aad41e5fdab3` |
| `alpine-3.24.2-desktop-fast-dirty-journal.ext4.gz` (kept, 994,836,889 bytes) | `1IiP9NAXN1YbqWYAEBfCNPm_RMlDhXYr6` | `721b2c12359178511e9741846385155c9f2847d86c978bae1a6bf30c02c6f6d8` | `bc60fbe9a0cfa0290328775ccd97a00ed6741dbb5c114003ca49748e230c0063` |

Links:

- labwc (clean, same ID as already shared): https://drive.google.com/file/d/1z5ekg6nr5qcv86ST-yy_O3ZLk9nIJYvR/view
- fast (clean, same ID as already shared): https://drive.google.com/file/d/1T6V-9MLZqjtNOYIB5vkJ4FDI6phrYcld/view
- labwc dirty-journal (kept): https://drive.google.com/file/d/1cP4YnylIgWlkcwQ2vS1aaybNpy2THOLq/view
- fast dirty-journal (kept): https://drive.google.com/file/d/1IiP9NAXN1YbqWYAEBfCNPm_RMlDhXYr6/view
- `SHA256SUMS` (updated in place, ID `1C3U1FQ7hibVJqSluDDDLOCMS76rmp6P-`): https://drive.google.com/file/d/1C3U1FQ7hibVJqSluDDDLOCMS76rmp6P-/view
- `README.txt` (new, ID `12l8imppa2SUliqCgwyXZmeycEuGSF3-x`): https://drive.google.com/file/d/12l8imppa2SUliqCgwyXZmeycEuGSF3-x/view

`alpine-3.24.2-desktop.ext4.gz` (XFCE) was already clean and was not replaced.

The dirty journals came from baking the fast/labwc images with `exec poweroff -f` (skips init umount) and gzipping the ext4 without e2fsck. `scripts/desktop-guest/install-fast-desktop.sh` now syncs, `umount -a -r`, and `poweroff` without `-f`. New host helper `scripts/macos-metal/pack-rootfs-gz.sh` refuses to gzip an image that still has `INCOMPAT_RECOVER`, running e2fsck first when `e2fsck` or Lima `kernarium-linux` is available.

### Why the mini rebooted at 4:15 AM ET

This was not a kernel panic, not jetsam/OOM, and not the 8 GiB JIT cache budget (that budget was not used in the preceding runs). There is no panic report under `/Library/Logs/DiagnosticReports`. `last` shows a shutdown and a reboot at 4:15 AM ET. The shutdown stall spindump (`shutdown_stall_2026-11-13-041519_Davids-Mac-mini-2.shutdownStall`, sampling started 4:15:03 AM ET) recorded an already-running shutdown, with `uml-darwin` (official binary, parent zsh, footprint 4,084.94 MB, forked ~14 s earlier) still in the guest JIT loop.

The initiator is in `log show`:

```
2026-11-13 04:15:01.523556-0500 shutdown[89862]: reboot by root: securityd-guard: securityd still hung 211s after kickstart
2026-11-13 04:15:01.523756-0500 launchd[1]: System shutdown initiated by: shutdown[89862]<-bash[89707]
```

`/usr/local/sbin/securityd-guard.sh` (LaunchDaemon `com.davidhope.securityd-guard.plist`) probes `security list-keychains` every 60 s, kickstarts `system/com.apple.securityd` after two failed 10 s probes, and if securityd is still hung 180 s later issues `shutdown -r now`. The user log:

- 04:00:08 AM ET: probe ok (0.058 s)
- 04:10:10 AM ET: first fail (`probe_rc=142`, 10.1 s timeout); no stuck `security` CLI processes
- 04:11:20 AM ET: second fail, kickstart
- 04:14:51 AM ET: still hung, graceful reboot (211 s after kickstart)

`uml-darwin` started around 04:14:49 AM ET, after securityd had already been wedged for about five minutes, so it was a bystander, not the cause. The same guard has rebooted this mini on this pattern many times (including 4:15 AM ET 13 Nov, 11:22 AM ET 12 Nov, and earlier October dates). Rate limit is 6 hours, so the next automatic reboot cannot happen before 10:15 AM ET. Avoid touching Keychain / the `security` CLI; do not disable the guard unless asked. After reboot, memory was 16 GiB with swap unused, not an OOM condition.

### Simulator JIT through a48d90a

The 4:15 AM reboot cleared the wedged Simulator. Peek iPhone 17 (`8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB`) and iPad (A16) (`6532E3AA-A7DF-48F4-9E87-6C4EA94F4C74`) both booted cleanly. Nothing was installed on a physical iPhone.

The live Kernarium tree was still at the pre-evict JIT sources (official evict/packed/arena builds had been side copies). For this Simulator rebuild only, `patches/0013-jit-publish-arena/` (evict-on-full + packed publish + bump arena) was copied onto `darwin/cpu/arm64/jit/{jit_shared_translations.cpp,jit_shared_translations.hpp,jit_executor_cache.cpp}`. `cmake --build --preset kernarium-ios-simulator` first failed because `darwin/memory/mmu/user_map.cpp` (mtime 01:09 AM ET) includes `<mach/mach_vm.h>`, which the iPhoneSimulator 26.5 SDK rejects (`#error mach_vm.h unsupported`). `inventory_holes()` was switched to `vm_region_64` so the Simulator SDK can compile it; the official macOS binary was not rebuilt (inode 244909018 unchanged). Then KRuntime was packaged and `xcodebuild` produced `Release-iphonesimulator/Kernarium.app` at 4:36 AM ET (`SIMCTL_CHILD_KERNARIUM_EXECUTION_ENGINE=jit`, cache budget 1 GiB). MesaEGL/MesaGallium xcframeworks were reused from the 12 Nov 11:48 PM ET Simulator build.

CPU benches on Peek, same Alpine 3.24.2 slim-init image as the old Simulator table, 4:36–4:37 AM ET (`notes/macos-metal-desktop/kernarium-sim-jit-0013-benches.log`):

| Bench | LinuxRunner | Simulator JIT (old, slim init) | Simulator JIT through a48d90a (4:37 AM ET) |
| --- | ---: | ---: | ---: |
| Boot to auto-benches (guest uptime at `BENCH_START`) | ~3.2 s to terminal frontend | **1.00 s** | 1.15 s |
| `sh` loop, 20,000 increments | 1.03 s | 0.34 s | **0.20 s** |
| `sha256sum` of 32 MiB | 1.64 s | 0.38 s | **0.37 s** |
| `apk add --no-cache tree` | 3.08 s | **1.49 s** | 1.64 s |
| `apk add --no-cache openssl` | 3.39 s | **1.58 s** | 1.75 s |
| `openssl speed -evp` at 16 KiB | aes 169.3 MB/s; sha256 376.0 MB/s | aes 875.1; sha256 1696.3 | aes **984.1** MB/s; sha256 1658.3 MB/s |
| Desktop (`DESKTOP_READY`, guest uptime) | (not compared) | 28.60 s (XFCE / virgl→llvmpipe) | **5.97 s** (labwc; iPad A16, 1920×1080) |

The `sh` loop is clearly faster than the previous Simulator JIT (0.20 s vs 0.34 s, now 5.15× LinuxRunner). sha256sum is tied with the old JIT. apk was a bit slower this run and is partly network-bound; do not treat that as a regression of the arena. Boot to benches was 1.15 s vs 1.00 s, within DHCP noise (lease obtained just before `BENCH_START`).

The desktop number is not a like-for-like XFCE rematch: the current production image is labwc (`alpine-3.24.2-desktop-labwc.ext4`, journal-clean). On iPad (A16) at 4:38 AM ET, `DESKTOP_START` was 3.28 s, labwc's Wayland socket was up at 5.95 s, and `DESKTOP_READY` was **5.97 s** (`display=wayland-0 labwc=1`). A second boot at 4:39 AM ET was ready in **3.96 s**. The old 28.60 s figure was XFCE. The serial log is the source for those times; `simctl io screenshot` of the iPad showed only Simulator chrome over a black guest surface (Firefox had been started but a painted-frame rematch was not captured). Execution engine was jit, 1 GiB cache budget. No phone install.

## Simulator labwc pixels (pixman present path, 13 Nov 2026, 4:49 AM ET)

The 4:38–4:39 AM ET labwc boots on iPad (A16) reached `DESKTOP_READY` (5.97 s, then 3.96 s) with JIT through a48d90a, but `simctl io screenshot` showed only Simulator chrome over a black guest surface. The Simulator Virgl provider is software (`Virgl software rasterizer provider: software`, guest `[drm] features: +virgl +edid +resource_blob +host_visible`). There is no Metal scanout texture; present depends on `RESOURCE_FLUSH` → `presentReadback` / `publishCpuFrame`. labwc's default GLES/EGL virtio_gpu scanout did not reach that path. XFCE already presented because Xorg modesetting uses a dumb/linear resource and flush. The macOS Metal path (`presentMetal`, `-edid`) was left unchanged.

`scripts/desktop-guest/start-desktop-labwc.sh` now selects `WLR_RENDERER=pixman` when it sees a non-empty `/sys/class/drm/*/edid` or dmesg `features:.*+edid`, and launches Firefox with `MOZ_ACCELERATED=0 MOZ_WEBRENDER=0` in that case only. A Simulator-only APFS clone `alpine-3.24.2-desktop-labwc-sim-pixman.ext4` (journal-clean, incompat 0x2c2, not the 0444 production file) received the script via Lima. iPad Documents pointed a new symlink at that clone; `tmp/kernarium-overlay.ext4` was deleted before launch.

First painted boot, 4:49:02 AM ET launch, iPad (A16) 1920×1080, JIT, 1 GiB cache, 4096 MiB / 8 vCPUs, `https://example.com`:

| Event | Guest uptime | Wall (America/New_York) |
| --- | ---: | --- |
| `simctl launch` | — | 4:49:02 AM |
| `software_display WLR_RENDERER=pixman` | 2.44 s | — |
| `DESKTOP_READY` | **3.83 s** | 4:49:07 AM |
| `FIREFOX_START` | 3.88 s | 4:49:07 AM |
| Firefox chrome painted (New Tab, blank content) | — | 4:49:38 AM (~31 s after READY) |
| example.com painted | — | 4:50:22 AM (~75 s after READY) |

Proof screenshot: `/Users/davidhope/linux-ios-bakeoff/screenshots/kernarium-sim-labwc-pixman-painted.png` (same bytes as `kernarium-sim-labwc-pixman-55s.png`, taken 4:50:22 AM ET). Earlier chrome-only frame: `kernarium-sim-labwc-pixman-25s.png`. The guest surface shows the labwc/Firefox window with the Example Domain page (a Firefox Privacy Notice tab also opened).

A second boot (Simulator had been shut down and rebooted; `DESKTOP_READY` **6.55 s**) measured Firefox time-to-page with `simctl io screenshot` every 5–10 s after READY (`screenshots/ttp/plus-*.png`, log `notes/macos-metal-desktop/kernarium-sim-labwc-pixman-ttp.log`):

| After READY | What the screenshot shows |
| ---: | --- |
| 30 s | still a black guest surface |
| 35 s | Firefox chrome, New Tab, blank content |
| 55 s | tab/URL on example.com, status “Waiting for example.com...” |
| 70 s | first Example Domain body text; status “Transferring data from example.com...” |
| 80 s | full example.com page painted (icon, translations, Learn more) |

So on this software-WebRender Simulator path, Firefox chrome appears about 35 s after READY, first page text by 70 s, and the full page by **80 s** after READY. That is much slower than the macOS Metal/Zink Isolated Web Content times (~12–15 s). The first boot’s 31 s chrome / 75 s full-page bracket matches this second measurement.

The Simulator app started as the 4:36 AM ET JIT-through-a48d90a build and was rebuilt at 5:03 AM ET to honor `KERNARIUM_JIT_CACHE_BUDGET` (`patches/0015-kernarium-jit-cache-budget`). Rebuild it from this repo with `scripts/build-kernarium-simulator.sh /path/to/Kernarium` (applies `patches/0013-jit-publish-arena/`, `patches/0014-simulator-vm-region-64/`, and 0015; `cmake --build --preset kernarium-ios-simulator` only). Nothing was installed on a physical iPhone. Official 4K inode remains 244909018.

## Simulator Firefox time-to-page (profile, CJK, JIT cache, 13 Nov 2026, 5:00–5:23 AM ET)

The first painted pixman screenshot still had a Firefox Privacy Notice tab, and CJK glyphs on example.com rendered as boxes. `scripts/desktop-guest/firefox-kernarium-profile.sh` (commit 8648ad6) was in the repo but had not been copied into the Simulator-only clone `alpine-3.24.2-desktop-labwc-sim-pixman.ext4`. That script was installed, along with a cheap CJK font (`font-wqy-zenhei` 0.9.46-r0; apk 9.0 MiB, installed `wqy-zenhei.ttc` ~16.7 MiB under `/usr/share/fonts/wqy-zenhei/`). `font-noto-cjk` (~73/89 MiB) was rejected as not cheap. After that, the Privacy Notice tab was gone and the CJK line of example.com painted.

On iPad (A16), 1920×1080, JIT, 4096 MiB guest / 8 vCPUs, `https://example.com`, chrome and full-page times are seconds after `DESKTOP_READY`:

| Config | Chrome | Full page | Notes |
| --- | ---: | ---: | --- |
| Baseline (no profile, 1G, `MOZ_WEBRENDER=0` only) | ~35 s | ~80 s | Privacy Notice tab; CJK boxes |
| Profile + CJK + software WR + fission off, 1G | 40 s | 80 s | No privacy tab; CJK OK; 12.2M rejected, 184 reuses, shared ~105 KiB |
| Same + 4G cache | 35 s | 80 s | 5.60M reuses, 5.8k rejected; 2 GiB shared full at ~11 s; heavy swap |
| Basic layers + 4G (sticky env) | 35 s | 80 s | No improvement vs software WR |
| Falkon, 1G | no paint in 120 s | — | `FALKON_START` at 6.53 s; screenshots stayed black |

### Where the time goes

Chrome tracks Web Content process spawn, not labwc present. A guest `/proc` probe (`scripts/desktop-guest/firefox-startup-probe.sh`, ttyS0 every 2 s) on the profile+1G boot (READY 6.04 s) saw: firefox 6.33 s, Socket/forkserver 20.02 s, WebExtensions/RDD 26.27 s, Web Content 43.04 s (~37 s after READY, matching chrome). The full page still landed ~80 s after READY.

The default JIT cache budget is one quarter of guest RAM (1 GiB at `mem=4G`). With 8 vCPUs and a 256 MiB L1 cap, that 1 GiB is consumed by the private L1s and the shared translation cache is left at ~105 KiB (`accounted`/`max` ≈ 105792). `UML_JIT_SHARED_STATS=1` dumps `===JIT_SHARED_STATS===` about once a second: evictions≈insertions≈5.03M, rejected≈12.2M, reuses=184. The 1 GiB budget evicts on every insert and cannot reuse the parent's libxul translations in the content process.

`patches/0015-kernarium-jit-cache-budget` lets `KERNARIUM_JIT_CACHE_BUDGET` (then `UML_JIT_CACHE_BUDGET`, K/M/G suffix) override `jit_cache_budget_for()`. Pass it into the Simulator with `SIMCTL_CHILD_KERNARIUM_JIT_CACHE_BUDGET`. Official `uml-darwin` was not rebuilt from this source. A Simulator-only KRuntime rebuild at 5:03 AM ET honored `4G` (budget 4294967296). Shared max=2147523904 (2 GiB). Evictions stayed 0 until dump #11 (~11 s, before Web Content at 34.09 s); later evictions=2.3M, rejected only 5755, reuses=5.60M. The shared tier fills before the content process starts, so time-to-page stays ~80 s. 4 GiB is the conceptually right budget for a real shared tier, but it is not a TTP win on this path and is too heavy for this 16 GiB mini + Simulator: swap was 8192M total / 7334M used, with ~74 MiB free during the run. Do not raise the budget further on this host. Unset `SIMCTL_CHILD_KERNARIUM_JIT_CACHE_BUDGET` after a 4G boot; it sticks in the shell and made the "layers 1G" run actually 4G.

Software WebRender (`gfx.webrender.software=true`, `fission.autostart=false`, `dom.ipc.processCount=1`) versus basic layers (`/usr/local/etc/firefox-gfx=layers`) was a tie: 35/80 s either way. Pixman damage tracking is not the startup bottleneck (the surface stays black until Firefox presents). The content sandbox was left on: on Metal, turning it off did not cut TTP and showed a warning banner.

Falkon is already in the image (Qt WebEngine). It started (`FALKON_START` at 6.53 s, READY 6.12 s) but never presented in 120 s; screenshots stayed black (likely EGL/GLES on Wayland, the same class of present problem pixman solved for labwc/Firefox). No lighter already-installed Alpine browser painted faster. Epiphany/Midori are not in the image.

The local sim-pixman clone was restored at 5:23 AM ET to Firefox + software WR defaults (profile script, wqy-zenhei, startup probe, no `/usr/local/etc/desktop-browser` or `firefox-gfx` overrides), journal-clean, 0444, inode 248520. Production `alpine-3.24.2-desktop-labwc.ext4` remains 0444, inode 248509, mtime 3:58:46 AM ET. Drive was not updated: time-to-page is not much better than the baseline.

Screenshots (mini `~/linux-ios-bakeoff/screenshots/`, also box `/workspace/`):

- `kernarium-sim-ff-profile-chrome.png`, `kernarium-sim-ff-profile-painted.png` — profile + CJK + software WR + fission off, 1G
- `kernarium-sim-ff-4g-chrome.png`, `kernarium-sim-ff-4g-painted.png` — same + 4G cache
- Earlier baseline with the Privacy Notice tab: `kernarium-sim-labwc-pixman-painted.png`

Logs: `notes/macos-metal-desktop/kernarium-sim-ff-profile-1g.log`, `kernarium-sim-ff-profile-4g.log`, `kernarium-sim-ff-layers-1g.log` (actually 4G; sticky env), `kernarium-sim-falkon-1g.log`.

Rebuild the Simulator app with `scripts/build-kernarium-simulator.sh`. Launch with `SIMCTL_CHILD_UML_JIT_SHARED_STATS=1` to dump cache counters. The default cache remains 1 GiB (safer on this mini). Nothing was installed on a physical iPhone. Official 4K inode remains 244909018.


## macOS 26.7.3 upgrade and Designed-for-iPad (13 Nov 2026, 6:01–6:48 AM ET)

David approved a 26.x upgrade so Xcode 26.6 would accept this Mac as a Designed-for-iPad destination. The mini was on macOS Tahoe 26.3.1 (25D2128, Darwin 25.3.0) and is now on **macOS Tahoe 26.7.3 (25G342, Darwin 25.6.0)**. Catalog at 6:02 AM ET also listed macOS 27.2.1-26B131; that was not installed. 26.6.2 was a previous notification, not the current latest 26.x.

`softwareupdate -i 'macOS Tahoe 26.7.3-25G342' --restart --agree-to-license --stdinpass --user davidhope` must run as root (`--restart` exits 13 otherwise). The volume-owner password came from 1Password (vault Grokbot, item "Mac mini login (davidhope)") and was not logged. Download + prepare ran 6:04:32–6:25:01 AM ET; required free space was 26.4 GB, about 39 GB was free. Post-logout apply started at 6:25:22 (`Applying MSU update`). SSH dropped around 6:28; the mini was reachable again at **6:37:24 AM ET** on 26.7.3. `softwareupdate --history` records the install at 6:26:31 AM ET.

Pre-upgrade (6:01 AM ET): Tailscale 1.104.2, Xcode 26.6 (17F113), voxl-launch still at `~/voxl-compare/voxl-launch` (not moved), LaunchAgents `com.davidhope.voxl` (127.0.0.1:6911, `--output-size=1366x768`) and `com.davidhope.voxl-1080` (6912), Tailscale serve 8443→6911 and 8444→6912, `com.davidhope.securityd-guard` StartInterval 60. No uml-darwin / xcodebuild / booted Simulator was running.

Post-reboot checks:

- Tailscale: reachable over 100.110.59.5 (`mac`) and 100.117.9.1 (`davids-mac-mini-1`). CLI still 1.104.2 (client commit e26db7a57 vs daemon c3430f0d2, same mismatch as before). Serve mappings came back on their own.
- voxl: both LaunchAgents started; `voxl-launch` path unchanged. After boot, ScreenCaptureKit captured the 1920×1080 display at 1364×768 (6911) and 2698×1518 (6912) with no permission error. From the mini, `https://davids-mac-mini-1.taile209c0.ts.net:8443/` and `:8444/` return HTTP 401 (Basic auth), as does `http://127.0.0.1:6911/` and `:6912/`. Display resolution was not changed; voxl resize was not enabled; Screen Sharing was left alone.
- securityd-guard: still loaded, periodic, last exit 0; `runs` counted up after boot (2 then 3+). `/usr/sbin/securityd` was running. The Keychain/`security` CLI was not used for the upgrade or the app build.
- `/Volumes/KernariumCS` did **not** auto-remount (no LaunchAgent). Re-attach with `hdiutil attach ~/linux-ios-bakeoff/KernariumCS.sparseimage`. After that it was 50 GiB, 25 GiB used, contents intact.
- Xcode 26.6 (17F113) still launches.

### Designed-for-iPad build

Destination now includes:

`{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:00006020-0009715A216B401E, name:My Mac }`

`cmake --preset kernarium-ios-device -DUML_IOS_DEBUGGER_JIT=OFF` and the Linux-only packager `~/linux-ios-bakeoff/notes/package-ios-linux-device.sh` succeeded (official `package-ios-frameworks.sh` still wants the missing Android runtime). `xcodebuild -scheme Kernarium -configuration Release -destination 'platform=macOS,variant=Designed for iPad' CODE_SIGNING_ALLOWED=NO` **BUILD SUCCEEDED** at 6:46 AM ET (product: `.build/kernarium-xcode-derived/Build/Products/Release-iphoneos/Kernarium.app`). KosmicKrisp was embedded for the device. Nothing was installed on a paired phone.

Launch is still blocked on signing, so there are no Designed-for-iPad READY or CPU bench numbers yet:

- Automatic signing with `DEVELOPMENT_TEAM=4P2629648N` fails: `com.imxieyi.Kernarium` cannot be registered to the signed-in team, the wildcard `iOS Team Provisioning Profile: *` lacks Extended Virtual Addressing and Increased Memory Limit, and it does not include this Mac (`00006020-0009715A216B401E`).
- Unsigned install is rejected by `IDEInstallLocalMacService` (`0xe800801c`, no code signature).
- Ad-hoc (`codesign -s -`) is not allowed with the iOS 26.5 SDK, and the entitlements require a development certificate.
- `devicectl` does not list the host Mac. Do not install on Silver or Yellow.

That signing blocker was lifted later the same morning with a unique bundle ID on David's team. See the next section for launch, Metal, READY, and CPU benches.

## Designed-for-iPad launch, Metal, and gadget benches (13 Nov 2026, 6:50–7:17 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Host: Mac mini (M2 Pro, 16 GB) on macOS Tahoe 26.7.3 (25G342), Xcode 26.6 (17F113). Destination: `platform=macOS,variant=Designed for iPad` (`My Mac`, UDID `00006020-0009715A216B401E`) only. Nothing was installed on Silver, Yellow, or any other phone.

### Signing

`patches/0016-designed-for-ipad-bundle-id` makes the official IDs overridable. Official defaults stay `com.imxieyi.Kernarium` (and the Tests / UITests / Automation IDs). A checkout sets its own IDs and `DEVELOPMENT_TEAM` in the gitignored `Signing.local.xcconfig`. The bakeoff mini uses team `4P2629648N` (the same team Voxl Pocket uses) and `com.davidhope.kernarium`.

Xcode automatic signing registered that App ID and issued `iOS Team Provisioning Profile: com.davidhope.kernarium` (`15037936-0469-4427-9395-41245e88b070`), identity `Apple Development: email.djhope@gmail.com (M9KY49FP5F)`. The profile includes this Mac and the kernel capabilities. The signed app entitlements are:

- `com.apple.developer.kernel.extended-virtual-addressing`
- `com.apple.developer.kernel.increased-memory-limit`
- `get-task-allow`

`com.apple.security.cs.allow-jit` is still in `Kernarium.entitlements` but is stripped at sign time (it is not in the iOS team profile). Forcing it back with a post-sign `codesign` yields `0xe8008015` (profile no longer matches). An SSH-session `codesign` failed with `errSecInternalComponent`; the Release and test builds were run from a one-shot LaunchAgent in `gui/501` so they could use the already-unlocked Aqua login keychain. The Keychain `security` CLI was not used to unlock anything.

Signed `xcodebuild` **BUILD SUCCEEDED** at **6:56:57 AM ET**. `HostGraphicsStackTests` **TEST SUCCEEDED** at **7:07:14 AM ET** on `My Mac - Kernarium`. A first guest session ran 7:08:49–7:09:21 AM ET; a second (with `apk add openssl`) ran 7:15:53–7:17:04 AM ET.

### Metal / GPU

Metal is usable on this destination. It is the same KosmicKrisp path as `uml-darwin`, not the Simulator llvmpipe/pixman stack.

- `HostGraphicsStackTests`: `host GL provider: Mesa | zink Vulkan 1.4(Apple M2 Pro (MESA_KOSMICKRISP)) | 4.6 (Core Profile) Mesa 26.2.6`. Vulkan ICD entry points are packaged. A surfaceless desktop context initialized on the host GPU.
- Guest session host log: `Virgl Zink/KosmicKrisp provider: hardware`, `Native Metal display: 1920x1080`.
- Guest drm: `features: +virgl +edid +resource_blob +host_visible`, cap set id 4 (Venus).
- Increased Memory Limit is in effect: `GPU budget 11451 MiB of a 16384 MiB limit`. Guest was `mem=4096M ncpus=8` at 160 DPI.

### JIT blocker

The ios-device runtime was built with `UML_IOS_DEBUGGER_JIT=OFF` (MAP_JIT publication, `patches/0004-map-jit-designed-for-ipad.patch`). `use_jit=1` was set, but the runtime logged `running on gadgets, not the JIT: this runtime cannot make executable memory` (`JitMemoryStatus::unsupported`: `mmap(MAP_JIT)` / publication probe failed without `allow-jit`). CPU benches below are therefore the gadget-engine column, not the Simulator or `uml-darwin` JIT column.

`get-task-allow` is present, so a rebuild with `UML_IOS_DEBUGGER_JIT=ON` could use the debugger-prepared region while `xcodebuild test` has a debugger attached. That runtime was not rebuilt in this pass. A physical iPhone still cannot use MAP_JIT without the entitlement or StikDebug; do not install this build on a phone.

### Desktop READY and CPU benches

Image: production `alpine-3.24.2-desktop-labwc.ext4` on KernariumCS (inode 248509, journal-clean, 0444; copied into the new `com.davidhope.kernarium` container, not modified in place). Serial was captured with `patches/0017-kernarium-serial-log` (`KERNARIUM_SERIAL_LOG=guest-serial.log`, `KERNARIUM_GUEST_SESSION=1`).

| Event / bench | Designed-for-iPad (My Mac, gadgets, labwc) | Simulator gadgets | Simulator JIT (labwc / slim) | uml-darwin Metal (JIT, labwc) |
| --- | --- | --- | --- | --- |
| `DESKTOP_READY` (guest uptime, labwc Wayland) | **2.26 s** then **2.14 s** (`display=wayland-0 labwc=1`; `DESKTOP_START` 1.11 / 1.06 s) | 3.83–6.55 s (pixman present path); 3.96–5.97 s on the earlier production image (black surface until pixman) | same Simulator boots; older XFCE was 28.60 s | 2.40 / 2.56 / 2.61 s; clean image 2.94 s; later 2.98–3.51 s |
| `sh` loop, 20,000 increments | **0.74 s** (both runs) | 0.79 s | 0.20–0.34 s | (CPU pack, not this desktop image) |
| `sha256sum` of 32 MiB | **1.43 s** / **1.50 s** | 1.45 s | 0.37–0.38 s | |
| `apk add --no-cache openssl` | **3.19 s** (second run) | 2.51 s | 1.58 s | |
| `openssl speed -evp` at 16 KiB | aes **153.6 MB/s**; sha256 **573.5 MB/s** (OpenSSL 3.5.9) | aes 164.0; sha256 594.9 | aes 875.1–984.1; sha256 1658–1696 | evp aes ~1000–1040 MB/s; sha256 ~1780–1790 MB/s |

READY matches `uml-darwin` labwc (real Metal) and is clearly faster than the Simulator labwc/pixman boots. The CPU numbers sit on the gadget column (sh 0.74 vs 0.79 s, sha256 1.43–1.50 vs 1.45 s, evp close to 164 / 595). The second-run evp figures are a little lower; Metal shader compilation messages landed in the log during `openssl speed`. Guest identity: `Linux alpine 6.18.60-g8246678b2d74`, Alpine 3.24.2, 4 GiB RAM, 8 vCPUs, 1920×1080.

Logs on the mini: `~/linux-ios-bakeoff/notes/macos-metal-desktop/kernarium-ipad-mac-guest-session-20261113.log` (and `-serial-`, `-openssl-` siblings), plus `~/Library/Logs/kernarium-ipad-mac-gui-build.log`, `kernarium-ipad-mac-launch.log`, and the guest-session xcodebuild logs. Display resolution and voxl were not changed.

