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

## Designed-for-iPad debugger JIT on My Mac (13 Nov 2026, 7:20–7:33 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host and destination as the gadget-engine pass: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3 (25G342), Xcode 26.6, `platform=macOS,variant=Designed for iPad` (`My Mac`, UDID `00006020-0009715A216B401E`) only. Nothing was installed on Silver, Yellow, or any other phone. Display resolution and voxl were not changed.

### Runtime and attach

The ios-device runtime was rebuilt with `cmake --preset kernarium-ios-device -DUML_IOS_DEBUGGER_JIT=ON` (**7:20:52–7:20:59 AM ET**) and packaged with the Linux-only packager (**7:21:30–7:21:37 AM ET**). The framework has `UML_JIT_MEMORY_REGION_ROUTE` / `prepare_debugger_region`. `get-task-allow` is already in the signed app; `allow-jit` is still stripped, so MAP_JIT stays unusable.

`xcodebuild test` on this destination does not ptrace the host process. A first LaunchAgent session with the new runtime (starting **7:22 AM ET**, no waiter) logged `running on gadgets, not the JIT: no debugger is attached` and reached `DESKTOP_READY` at **7:23:13 AM ET** (guest uptime 2.36 s). Those CPU figures are not JIT and were not used below.

The same blessing protocol Henge / StikDebug uses on a device (`brk #0xf00d`, `x16 == 1` prepare, one `0x69` byte written through the debugger into each 16 KiB page, then `x16 == 0` detach) is what actually makes the region runnable. Henge's built-in StikJIT helper is the on-device attach path; it was not used here and nothing was installed on a phone. On My Mac the attach is host `lldb` running Kernarium's own `tests/integration/support/ios_jit_debugger.py` (`jit_serve`). A bare `lldb -o continue` stops on the trap and never prepares the pages.

`patches/0018-debugger-jit-wait` waits in `ContentView` when `KERNARIUM_WAIT_FOR_DEBUGGER=1` (default 30 s) and delays CPU benches with `KERNARIUM_GUEST_SESSION_BENCH_DELAY` so Firefox time-to-first-page can be captured first.

A new Aqua `gui/501` session started **7:30:14 AM ET**, attached at **7:30:22 AM ET** (`debugger attached=true`), prepared **10624 pages (166 MiB) in 0.8 s** at **7:30:30–7:30:31 AM ET**, detached, and then logged:

`Kernarium: execution engine jit (cache budget 285212672 bytes)` (272 MiB). Not gadgets. Guest boot followed immediately (`mem=4096M ncpus=8`, 1920×1080, 160 DPI). Metal was unchanged: `Virgl Zink/KosmicKrisp provider: hardware`, `Native display: direct Metal texture presentation`, `GPU budget 11451 MiB of a 16384 MiB limit`. Guest: `Linux alpine 6.18.60-g8246678b2d74`, Alpine 3.24.2, production `alpine-3.24.2-desktop-labwc.ext4`.

### Desktop READY, CPU benches, and Firefox TTP

`TEST SUCCEEDED` at **7:33:02 AM ET**. Image and benches are the same as the gadget column.

| Event / bench | Designed-for-iPad (My Mac, **JIT**, labwc) | Designed-for-iPad (My Mac, gadgets, labwc) | Simulator gadgets | Simulator JIT (labwc / slim) | uml-darwin Metal (JIT, labwc) |
| --- | --- | --- | --- | --- | --- |
| `DESKTOP_READY` (guest uptime, labwc Wayland) | **3.92 s** (`DESKTOP_START` 1.98 s; labwc socket 3.89 s; `display=wayland-0 labwc=1`) at **7:30:35 AM ET** | **2.26 s** then **2.14 s** (`DESKTOP_START` 1.11 / 1.06 s) | 3.83–6.55 s (pixman); 3.96–5.97 s earlier | same Simulator boots; older XFCE 28.60 s | 2.40 / 2.56 / 2.61 s; clean 2.94 s; later 2.98–3.51 s |
| `sh` loop, 20,000 increments | **0.49 s** | **0.74 s** (both runs) | 0.79 s | 0.20–0.34 s | (CPU pack, not this desktop image) |
| `sha256sum` of 32 MiB | **0.41 s** | **1.43 s** / **1.50 s** | 1.45 s | 0.37–0.38 s | |
| `apk add --no-cache openssl` | **2.91 s** | **3.19 s** | 2.51 s | 1.58 s | |
| `openssl speed -evp` at 16 KiB | aes **370.0 MB/s**; sha256 **82.1 MB/s** (OpenSSL 3.5.9; 8192-byte sha256 was 302.8 MB/s) | aes **153.6 MB/s**; sha256 **573.5 MB/s** | aes 164.0; sha256 594.9 | aes 875.1–984.1; sha256 1658–1696 | evp aes ~1000–1040 MB/s; sha256 ~1780–1790 MB/s |
| Firefox time-to-first-page (`https://example.com`, after `FIREFOX_START` at READY+0.00 s / **7:30:35 AM ET**) | Chrome (New Tab, empty) by **7:31:55 AM ET** (80 s; first successful window capture). `example.com` tab still blank and "Waiting…" at **7:32:13 AM ET** (98 s); still blank, "Transferring data…" at **7:32:41 AM ET** (126 s). **Example Domain body painted at 7:32:46 AM ET (131 s)**. | (not measured this morning) | pixman: chrome ~31–43 s, full page ~75–80 s | | Metal painted ~12 s after READY |

JIT helps the integer/hash CPU benches (`sh` 0.74→0.49 s, `sha256sum` 1.43–1.50→0.41 s, close to Simulator JIT 0.37–0.38 s) and more than doubles evp AES at 16 KiB (153.6→370.0 MB/s), but that AES figure is still well short of Simulator JIT (~875–984) and `uml-darwin` (~1000–1040). evp SHA-256 at 16 KiB **regressed** (573.5→82.1 MB/s); the 8192-byte column was 302.8 MB/s, also below the gadget 16 KiB figure. `UML_JIT_SHARED_STATS=1` showed many misses and evictions with a tiny retained working set during the boot and Firefox window. READY was a little slower than the gadget boots (3.92 s vs 2.14–2.26 s), consistent with JIT warmup before labwc is up.

Firefox TTP on this Metal desktop was much slower than `uml-darwin` (~12 s) and Simulator pixman (~31–80 s). The 131 s first paint spent a long time on New Tab, then on "Waiting for example.com…" / "Transferring data…", so startup plus guest NAT/network dominate over GPU present. `FIREFOX_START` is immediate after READY; the production labwc image still has no `firefox-startup-probe.sh`. Early frames (0–80 s) were not captured: a LaunchAgent `screencapture` has no Screen Recording TCC, so window shots were taken from a machine-targeted shell instead. The Kernarium window is 1024×800 on the host (guest remains 1920×1080). Shots: `~/linux-ios-bakeoff/screenshots/kernarium-ipad-jit-ttp/manual/` (`t-073155-w128.png` chrome only, `t-073213-w128.png` waiting, `t-073241-w128.png` still blank, `t-073246-w128.png` painted).

Logs on the mini: `~/linux-ios-bakeoff/notes/macos-metal-desktop/kernarium-ipad-mac-debugger-jit-session-20261113.log`, `-serial-`, `-guest-session-`, and `kernarium-ipad-jit-serve-20261113.log`. The attach recipe is in `patches/0018-debugger-jit-wait/README.md` and REPRODUCE.md.

## Designed-for-iPad 2 GiB JIT budget / 128 MiB L1 (13 Nov 2026, 7:43–7:52 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host and destination as the 272 MiB JIT pass: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3, Xcode 26.6, Designed for iPad on My Mac only. Nothing was installed on a phone. Display resolution and voxl were not changed.

### Why 272 MiB evicted so hard

The logged 272 MiB budget was the gadget cache cap at 8 vCPUs (`gadget_cache_cap_mib`), applied because the process has a memory limit, not 1/4 of the 4 GiB guest. Private L1s consumed almost all of it, leaving a ~105 KiB shared translation cache (`max≈105792`). `UML_JIT_SHARED_STATS=1` showed evictions≈insertions and millions of rejects.

A 2 GiB whole-process budget with the default 256 MiB L1 cap still leaves no shared tier (8×256 MiB = 2 GiB) and overshoots the old 1 GiB debugger-region limit: a 7:43:20 AM ET attempt logged `the executable memory could not be prepared` and fell back to gadgets, with no `brk #0xf00d` request. `patches/0019-debugger-jit-cache-budget` raises that limit to 2 GiB and honors `KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET` / `UML_JIT_EXECUTOR_CACHE_BUDGET`.

### Runtime and attach

ios-device runtime rebuilt with `UML_IOS_DEBUGGER_JIT=ON` at **7:48:28–7:49:08 AM ET** (package **7:49:08–7:49:16 AM ET**). Aqua session with `TEST_RUNNER_KERNARIUM_JIT_CACHE_BUDGET=2G` and `TEST_RUNNER_KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET=128M` started **7:49:24 AM ET**. `lldb` + `jit_serve` attached at **7:50:02 AM ET**, with SIGUSR1/SIGUSR2/SIGALRM passed through (UML IPIs; a first 2 GiB attempt that stayed attached without that pass-through flooded the serve log with stops). Prepared **39912 pages (623.6 MiB) in 2.9 s** at **7:50:06–7:50:09 AM ET**, then detached. Log:

`Kernarium: execution engine jit (cache budget 2147483648 bytes, executor cap 134217728 bytes)`

That is a 2 GiB whole-process budget, 128 MiB private L1 cap (8×128 MiB = 1 GiB), and ~1 GiB left for the shared tier. Guest `mem=4096M ncpus=8`, 1920×1080, 160 DPI. Metal unchanged. Kernarium RSS peaked around 5.24 GiB; `vm.swapusage` stayed **0.00M used**; system-wide memory was about 47% free. No swap.

`===JIT_SHARED_STATS===` at start: `accounted=65536 max=1073847616` (~1 GiB cap). At atexit: matches=11,933,213, reuses=11,932,894, misses=2,403,841, insertions=2,385,102, evictions=2,041,478, **rejected=11,242**, payload≈720 MiB, accounted≈1 GiB. Evict-on-full is working; this is no longer a reject storm.

### Networking

Guest NAT/DNS was not the earlier 131 s Firefox stall. After READY, `KERNARIUM_GUEST_SESSION_NET_PROBE=1` recorded: `resolv` nameserver 10.0.2.3, default route via 10.0.2.2, `nslookup example.com` **0.01 s** (A + AAAA), ping 10.0.2.2 **0.2–1.0 ms** (0% loss), `wget http://example.com` **0.13 s**, HTTP 200 (Cloudflare EWR HIT). No slirp/DNS code change was made. (A probe during the failed gadgets+lldb run was slower — nslookup 0.31 s, ping 32–79 ms, wget 0.50 s — because lldb was stopping on SIGUSR.)

### Desktop READY, CPU benches, and Firefox TTP

`TEST SUCCEEDED` at **7:52:50 AM ET**.

| Event / bench | D4iPad JIT **2G/128M L1** | D4iPad JIT 272 MiB (no shared) | D4iPad gadgets | Sim gadgets | Sim JIT | uml-darwin Metal JIT |
| --- | --- | --- | --- | --- | --- | --- |
| `DESKTOP_READY` (guest uptime) | **3.04 s** (`DESKTOP_START` 1.38 s; labwc socket 3.02 s) at **7:50:13 AM ET** | 3.92 s (START 1.98 s) | 2.26 s then 2.14 s | 3.83–6.55 s pixman | same sim boots | 2.40–3.51 s |
| `sh` loop, 20,000 increments | **0.68 s** | 0.49 s | 0.74 s | 0.79 s | 0.20–0.34 s | — |
| `sha256sum` of 32 MiB | **0.64 s** | 0.41 s | 1.43 / 1.50 s | 1.45 s | 0.37–0.38 s | — |
| `apk add --no-cache openssl` | **13.39 s** (network; not a CPU figure) | 2.91 s | 3.19 s | 2.51 s | 1.58 s | — |
| `openssl speed -evp` at 16 KiB | aes **701.5 MB/s**; sha256 **708.5 MB/s** (OpenSSL 3.5.9) | aes 370.0; sha256 82.1 (8192-byte sha256 302.8) | aes 153.6; sha256 573.5 | 164.0 / 594.9 | 875–984 / 1658–1696 | ~1000–1040 / ~1780–1790 |
| Firefox TTP (`https://example.com`, after `FIREFOX_START` at READY+0.00 s / **7:50:13 AM ET**) | Black labwc at **7:50:40 AM ET** (27 s). **Chrome (New Tab) at 7:50:44 AM ET (31 s)**. example.com tab still blank, "Waiting…" at **7:51:18 AM ET** (65 s). **Example Domain body painted at 7:51:23 AM ET (70 s)**. | Chrome still New Tab at 80 s; body painted at 131 s | (not measured) | chrome ~31–43 s, full page ~75–80 s | | ~12 s after READY |

evp AES at 16 KiB nearly doubled vs the 272 MiB JIT (370→701.5 MB/s) and evp SHA-256 recovered from the 82.1 MB/s regression to **708.5 MB/s** (above the gadget 573.5, still short of Simulator / uml-darwin JIT). `sh` and busybox `sha256sum` were a little slower than the 272 MiB JIT run (0.68 / 0.64 vs 0.49 / 0.41); they remain faster than gadgets. `apk` is network-bound.

Firefox TTP improved (chrome 80 s→**31 s**, body 131 s→**70 s**) but is still far from uml-darwin's ~12 s. Guest wget of example.com was 0.13 s, so the remaining delay is Firefox process/content startup, not NAT/DNS. Shots: `~/linux-ios-bakeoff/screenshots/kernarium-ipad-jit-2g-ttp/manual/` (`t-075040-w138.png` black, `t-075044-w138.png` chrome, `t-075118-w138.png` waiting, `t-075123-w138.png` painted).

Logs on the mini: `~/linux-ios-bakeoff/notes/macos-metal-desktop/kernarium-ipad-mac-debugger-jit-2g-session-20261113.log`, `-serial-`, `-guest-session-`, `kernarium-ipad-jit-serve-2g-20261113.log`, and `kernarium-ipad-jit-2g-memory-20261113.log`. The failed 2 GiB/default-L1 attempt is archived as `kernarium-ipad-mac-2g-oversize-region-failed-20261113.log`.

## Persistent JIT translation cache and KernariumCS login attach (13 Nov 2026, 8:04–8:19 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3. Work stayed on this host (uml-darwin and, next, Designed for iPad on My Mac). Nothing was installed on a phone. Display resolution, voxl, Screen Sharing, and the official 4K `uml-darwin` identity were not changed. The official `macos-integration-16k` binary remains the 1:30 AM ET artifact.

### KernariumCS LaunchAgent

`KernariumCS.sparseimage` is unencrypted (`image-encrypted: false`). After the 26.7.3 upgrade it needed a manual `hdiutil attach`. A login LaunchAgent now attaches it without the Keychain or the `security` CLI: `scripts/macos-metal/attach-kernariumcs.sh` and `com.davidhope.kernariumcs-attach.plist`. ProgramArguments point at the stable bakeoff copy `/Users/davidhope/linux-ios-bakeoff/scripts/macos-metal/attach-kernariumcs.sh`. Installed under `~/Library/LaunchAgents/` and bootstrapped in `gui/501`. The script is idempotent if the volume is already mounted; the 8:05:12 AM ET login/bootstrap log line was `already mounted at /Volumes/KernariumCS`. The cache lives on that volume (the data volume is tight; do not put a multi-GB JIT cache there).

### Persistent store

`patches/0020-jit-persistent-cache` writes admitted shared-cache translations to an append-only `data.jtc` plus `index.jtc`. The on-disk key is the 16-byte content hash of the guest code page, the page offset, and the codegen profile — not the process-lifetime `code_page_identity` stamp, which cannot survive a reboot. Lookup requires an exact match of the stored guest instruction bytes; an optional source fingerprint (ext4 UUID, size, mtime via `UML_JIT_PERSISTENT_CACHE_SOURCE`) retires a mismatched image to `*.stale` and starts empty. CRC or header damage is a skip / empty store (safe fallback). Reloc cells are zeroed before a record is written; any leftover 64-bit value in the macOS user range `[0x100000000, 0x200000000)` is refused on remember and on lookup.

The official 4K identity was not rebuilt. macos-integration `uml-darwin` was rebuilt at **8:15 AM ET** after a first warm boot against a tainted cache (writes that still carried a cold-process host pointer) panicked at **8:13:15–8:13:18 AM ET** (`Kernel mode signal 10` at a macOS user `pc`). That ~719 MiB generation was wiped. The numbers below use the post-fix binary and a clean cache on `/Volumes/KernariumCS/jit-cache/uml-darwin`, with `UML_JIT_CACHE_BUDGET=8G`, `mem=4G ncpus=8`, production `start-desktop-labwc.sh` (e10s on), and the stable read-only labwc rootfs as the source fingerprint. `vm.swapusage` stayed **0.00M used** on both runs. Window shots were taken from a machine-targeted shell (`screencapture -x -l WID`): a LaunchAgent has no Screen Recording TCC.

### uml-darwin cold vs warm Firefox TTP

Cold (empty cache, **8:15:34–8:17:12 AM ET**). `DESKTOP_READY` **4.62 s** at **8:15:39 AM ET**. `FIREFOX_START` 4.84 s (`from_ready=0.00`) at **8:15:39 AM ET**. `FF_ISOLATED` **23.43 s** after READY (up=28.05, ~**8:16:02 AM ET**). Chrome (example.com tab, empty body) at **8:16:22 AM ET** (**43 s** after start). First English Example Domain body text at **8:16:30 AM ET** (**51 s**). Full multilingual body at **8:16:42 AM ET** (**63 s**). Persist: stores=147,480, same-boot hits=179,445, rejected=0, `data.jtc` ≈ 58.7 MiB. READY is slower than the historical 2.5–3.5 s uml-darwin boots; Isolated and first paint are also slower than the historical ~12 s Metal TTP, consistent with synchronous persist I/O on the cold path.

Warm (same cache and binary, **8:17:50–8:19:27 AM ET**). The store reopened the cold files (`entries=147,456`, `data=58,720,816` on the first stats line, stores=0, hits already climbing). No panic. `DESKTOP_READY` **4.66 s** at **8:17:55 AM ET**. `FIREFOX_START` 4.79 s at **8:17:55 AM ET**. `FF_ISOLATED` **18.03 s** after READY (up=22.69, ~**8:18:13 AM ET**). Chrome (New Tab) at **8:18:20 AM ET** (**25 s** after start). First English Example Domain body text at **8:18:27 AM ET** (**32 s**). Full multilingual body at **8:18:41 AM ET** (**46 s**). Final persist: hits=320,315, stores=10,340, rejected=0, entries=157,796, `data.jtc` ≈ 62.6 MiB. Shared-cache insertions were still ~1.53M with ~1.23M misses — the persistent set is only the translations that are safe to store, so a warm Firefox start is faster but not yet almost all cache hits.

| Event (uml-darwin Metal JIT, labwc, persist on) | Cold (empty disk cache) | Warm (reused disk cache) |
| --- | --- | --- |
| `DESKTOP_READY` | **4.62 s** at **8:15:39 AM ET** | **4.66 s** at **8:17:55 AM ET** |
| Isolated Web Content (`from_ready`) | **23.43 s** (~8:16:02 AM ET) | **18.03 s** (~8:18:13 AM ET) |
| Firefox chrome first visible | **43 s** (8:16:22 AM ET) | **25 s** (8:18:20 AM ET) |
| First example.com body text | **51 s** (8:16:30 AM ET) | **32 s** (8:18:27 AM ET) |
| Full Example Domain body | **63 s** (8:16:42 AM ET) | **46 s** (8:18:41 AM ET) |
| Persist hits / stores / rejected | 179,445 / 147,480 / 0 | 320,315 / 10,340 / 0 |

Shots: `~/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-cold-manual2/` and `persist-ttp-warm-manual2/`. Session logs: `session-persist-cold-20261113-081534.log` and `session-persist-warm-20261113-081750.log`.

### Designed-for-iPad cold vs warm Firefox TTP

ios-device runtime rebuilt with 0020 at **8:22:18 AM ET** and packaged **8:22:35 AM ET** (`UML_IOS_DEBUGGER_JIT=ON`, 2G/128M L1 unchanged). The official 4K identity was not rebuilt. Aqua `GuestSessionTests` plus `lldb`/`jit_serve` (SIGUSR1/SIGUSR2/SIGALRM passed through). A first LaunchAgent attempt at **8:24:15 AM ET** missed the process: the waiter gave up after 30 s while xcodebuild was still compiling, and the guest ran on gadgets. That run is discarded.

The debugger-JIT waiter was extended to 300 s. A first JIT cold at **8:28:16 AM ET** attached and logged `execution engine jit (cache budget 2147483648 bytes, executor cap 134217728 bytes)`, but wrote no `data.jtc`: the app sandbox cannot write `/Volumes/KernariumCS`. Persist stats were absent (the store stays off if the directory cannot be opened). Firefox chrome (New Tab) was at **8:29:13 AM ET** (37 s after `FIREFOX_START` at **8:28:36 AM ET** / READY 3.83 s); full Example Domain body at **8:30:05 AM ET** (89 s). That run is a persist-off JIT baseline, not a persist result.

The cache was then pointed at the app container, which the test already uses for the rootfs and guest logs:

`~/Library/Containers/6C8222CA-6C25-43B8-8EAD-1F9880730E07/Data/Documents/jit-cache`

with `UML_JIT_PERSISTENT_CACHE_SOURCE` set to the in-container `alpine-3.24.2-desktop-labwc.ext4`. `vm.swapusage` stayed **0.00M used**. Window shots were taken from a machine-targeted shell.

Cold (empty container cache, **8:35:07–8:43:26 AM ET**). Attached **8:35:15 AM ET**, prepared **39912 pages (623.6 MiB) in 2.9 s** at **8:35:24 AM ET**, then detached. JIT 2G/128M. `DESKTOP_READY` **4.38 s** at **8:35:28 AM ET**. `FIREFOX_START` 4.44 s at **8:35:28 AM ET**. Chrome (New Tab) at **8:36:11 AM ET** (**43 s**). First English Example Domain body text at **8:36:44 AM ET** (**76 s**). Full multilingual body at **8:36:58 AM ET** (**90 s**). Persist grew to hits=237,157, stores=162,137, rejected=4, `data.jtc` ≈ 62 MiB. The guest later stalled in `openssl speed` aes-256-cbc 8192-byte (Kernarium at ~0.3% CPU, log frozen from **8:37 AM ET**); the process was SIGTERM'd at **8:43:15 AM ET**. Periodic flush had already written the 62 MiB store; no `why=atexit` line was observed.

Warm (same cache and binary, **8:43:45–8:46:33 AM ET**). The store reopened the cold files (`entries=159,744`, `data=63,651,576` on the first stats line, stores=0, hits already climbing). No panic. Attached **8:43:54 AM ET**, prepared the same 39912 pages in 2.9 s at **8:44:01 AM ET**. `DESKTOP_READY` **4.41 s** at **8:44:06 AM ET**. `FIREFOX_START` 4.46 s at **8:44:06 AM ET**. Chrome (New Tab) at **8:44:43 AM ET** (**37 s**). First English Example Domain body text at **8:45:29 AM ET** (**83 s**). Full multilingual body at **8:45:42 AM ET** (**96 s**). Final persist: hits=350,266, stores=4,609, rejected=4, entries=164,353. The session was SIGTERM'd at **8:46:33 AM ET** after body paint, before the openssl stall seen on the cold run.

Warm Firefox TTP on Designed-for-iPad is not clearly faster than the persist-on cold (chrome 43 s→37 s; first body 76 s→83 s; full body 90 s→96 s), and it remains slower than the earlier 2G/128M persist-off JIT (chrome 31 s, body 70 s at 7:50–7:51 AM ET). The disk cache is doing real work (350k hits after a clean reopen), but the persistent set is still only the translations that are safe to store, and shared-cache evictions at the 1 GiB cap continue. `/Volumes/KernariumCS` is the right place for the uml-darwin cache; on My Mac the store has to live in the container.

Shots: `~/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-d4ipad-cold-manual3/` and `persist-ttp-d4ipad-warm-manual/`. Session logs: `kernarium-ipad-persist-cold-session-20261113-083505.log` and `kernarium-ipad-persist-warm-session-20261113-084345.log`.

## Persist-off A/B and default-path hash hook (13 Nov 2026, 8:47–9:00 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3. Work stayed on this host. Nothing was installed on a phone. Display resolution, voxl, Screen Sharing, and the official `macos-integration-16k` binary (1:30 AM ET) were not changed.

The persist-on uml-darwin figures above (cold full page **63 s**, warm **46 s**) looked like a regression against the historical ~12–14 s “to page” baseline. Persist was already off unless `UML_JIT_PERSISTENT_CACHE` / `KERNARIUM_JIT_PERSISTENT_CACHE` is set to a directory, but find/publish still hashed every guest code page and entered `ThreadPersistentIdentityScope`. That default-path tax is now skipped when no store is attached (`patches/0020-jit-persistent-cache/apply.py`, and the live Kernarium `jit_executor_cache.cpp`). Persist stays **opt-in**. It is not enabled in the production launchers.

### Official 4K binary

The official 4K `macos-integration` path `.build/presets/macos-integration/bin/uml-darwin` (inode 244909018, 54,280,296 bytes, 1:09 AM ET) was overwritten at **8:15 AM ET** by the persist-fix rebuild (inode 245339732, 54,324,568 bytes). No copy of size 54,280,296 / inode 244909018 remained under bakeoff, KernariumCS, `/opt`, `/usr/local`, or `~/Library`, and no Time Machine local snapshots were listed. That path was **not** overwritten again this pass; a copy of the 8:15 binary was saved as `uml-darwin-persistfix`. The closest pre-0020 4K stand-in is `uml-darwin-arena` (4:07 AM ET, inode 244936914, 54,300,416 bytes). `macos-integration-16k` is a different identity (`UML_GUEST_16K_PAGES=True`) and was not used as a 4K stand-in.

### A/B (same labwc image, native Metal, mem=4G ncpus=8, 8G budget)

Image: `/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop-labwc.ext4` (0444, clean journal). Production-style `start-desktop-labwc-persist.sh` (e10s on, Isolated probe). `UML_GPU_DISPLAY=native`, 1920×1080. Window shots from a machine-targeted shell (`screencapture -x -l WID`); a LaunchAgent has no Screen Recording TCC. `vm.swapusage` stayed **0.00M used** on every run. Chrome / first body / full page times are seconds after process start.

| Config | Window (ET) | READY | Isolated (`from_ready`) | Chrome | First English body | Full multilingual body |
| --- | --- | --- | --- | --- | --- | --- |
| Pre-0020 `uml-darwin-arena` 8G, persist off | 8:50:36–8:52:35 AM | **3.98 s** at 8:50:41 AM | **15.07 s** | **21 s** (8:51:02 AM) | **38 s** (8:51:19 AM) | **45 s** (8:51:26 AM) |
| 8:15 persist-fix binary 8G, persist off (hash hooks still on) | 8:53:02–8:55:00 AM | **4.19 s** at 8:53:07 AM | **17.97 s** | **23 s** (8:53:30 AM) | **32 s** (8:53:39 AM) | **48 s** (8:53:55 AM) |
| Hook-fix side binary `uml-darwin-hookfix` 8G, persist off | 8:58:51–9:00:50 AM | **3.36 s** at 8:58:57 AM | **14.65 s** | **26 s** New Tab (8:59:17 AM); example.com tab empty at 8:59:25 AM | **41 s** (8:59:32 AM) | **48 s** (8:59:39 AM) |
| 8:15 binary 8G, persist on, cold | 8:15:34–8:17:12 AM | **4.62 s** at 8:15:39 AM | **23.43 s** | **43 s** (8:16:22 AM) | **51 s** (8:16:30 AM) | **63 s** (8:16:42 AM) |
| 8:15 binary 8G, persist on, warm | 8:17:50–8:19:27 AM | **4.66 s** at 8:17:55 AM | **18.03 s** | **25 s** (8:18:20 AM) | **32 s** (8:18:27 AM) | **46 s** (8:18:41 AM) |

Hook-fix persist-off had zero `JIT_PERSIST_STATS` lines. Isolated **14.65 s** is back in line with (slightly ahead of) pre-0020 arena **15.07 s**; the unconditional page-hash tax on the 8:15 persist-off run (~3 s Isolated) is gone. Full multilingual body stays in the mid-40s for arena, hook-fix persist-off, and persist-on warm.

Persist-on warm does **not** clearly beat the persist-off baseline: Isolated 18.03 s is worse than hook-fix 14.65 s and tied with the untaxed-off 8:15 run at 17.97 s; chrome 25 s vs 23–26 s is noise; full body 46 s vs 48 s is also noise. Persist-on cold is a real I/O tax (Isolated 18→23 s, full 48→63 s). Persist therefore stays off unless the directory env is set.

The historical ~12–14 s “to page” (2:47–3:53 AM ET, official 4K, typically VNC, mem=4G ncpus=8, often meaning Isolated or first example.com text, with “fully painted (icon + translations)” also quoted at ~12 s) does **not** reproduce today as native full-page multilingual paint. Even pre-0020 arena 8G is Isolated 15.07 s (matches the earlier official 8G Isolated **16.0 s**) but full multilingual body **45 s** under today’s native-screenshot method. macOS was upgraded to 26.7.3 at **6:37 AM ET**, after those 12 s measurements and before every persist/A/B number here. The official 4K binary cannot be re-run, so environment vs official-binary cannot be fully isolated. 8G is not the 63 s cause: every comparable row used 8G. KernariumCS on a sparseimage is the rootfs/cache volume for all of these uml-darwin runs, including arena at 45 s, so it is not unique to persist-on.

The hook-fix binary was side-linked at **8:58 AM ET** as `uml-darwin-hookfix` (inode 245386222, 54,324,576 bytes) without touching the official 4K path (still inode 245339732, 8:15 AM ET) or macos-integration-16k.

Shots: `~/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-ab-arena8g-manual/`, `persist-ttp-ab-newoff8g-manual/`, `persist-ttp-ab-hookoff8g-manual/`. Session logs: `session-ab-arena8g-20261113-085036.log`, `session-ab-newoff8g-20261113-085302.log`, `session-ab-hookoff8g-20261113-085851.log`.

### Designed-for-iPad openssl aes-256-cbc 8192-byte stall

The persist-on D4iPad cold guest (`kernarium-ipad-persist-cold-session-20261113-083505.log`) ran `openssl speed -seconds 3 -evp sha256 aes-256-cbc`, completed the 16/64/256/1024-byte aes-256-cbc columns, then stalled on `Doing aes-256-cbc ops for 3s on 8192 size blocks:` with Kernarium at ~0.3% CPU from about **8:37 AM ET** until SIGTERM at **8:43:15 AM ET** (`Darwin: ELF exit(143)`). Persist-off on the same destination and command (`kernarium-ipad-persist-cold-session-20261113-082816.log`) finished that 8192-byte column (`147060 aes-256-cbc ops in 2.99s` and the 16384-byte column after it) and reached `TEST SUCCEEDED`. Both runs were evicting at the ~1 GiB shared-cache cap; persist-on also had `rejected=4`.

That hang is persist-on only. It was not reproduced with persist off, and it was not re-run on D4iPad after the hook fix (no hypothesis was safe enough to risk another multi-minute stall). Possible causes: a persist-admitted translation that is incorrect on this destination (the leftover-host-pointer refusal range `[0x100000000, 0x200000000)` is shaped like uml-darwin macOS user VAs and may miss Designed-for-iPad JIT-region pointers), or a long stall from `remember()` fsync/index write under the persist mutex during heavy eviction. Persist stays opt-in and should not be turned on for D4iPad until that path is shown safe. The hook-fix change does not alter persist-on behaviour; it only skips hashing when the store is off.


## Compiler reuse and reserved emit buffers (13 Nov 2026, 9:22–9:44 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3. Work stayed on this host. Nothing was installed on a phone. Display resolution, voxl, Screen Sharing, Keychain, and the official `macos-integration-16k` binary (1:30 AM ET, inode 244913917) were not changed. `vm.swapusage` stayed **0.00M used** on every run. Persist stayed **off**.

### Official-from-main identity, frozen

A clean official 4K `macos-integration` `uml-darwin` was rebuilt from hook-fix + 0011–0013 sources already in the tree at **9:22:03 AM ET** (inode 245391025, 54,324,568 bytes) and immediately copied to `uml-darwin-official-c134a87` (inode **245391030**) and `uml-darwin-official-20261113` (inode 245391031). Those named copies were not overwritten by the later side-link. Evict-on-full (0011), packed-publish (0012), and the publish arena (0013) are part of this official identity and stay promoted: earlier same-session compile-cold figures were official 1.99/2.08 s, packed 1.94 s, arena 1.91/1.94 s (~5–8%).

### Profile (official-c134a87, then alloc)

SIGPROF 999 Hz, compile-cold window after subtracting the pre-compile (boot+apk) histogram, `mem=2G ncpus=8`, persist off. Official **9:23:22–9:23:31 AM ET**, compile-cold wall **2.28 s**, 1990 delta samples: memcpy/memset **44.82%** (814 `_platform_memmove`), malloc **9.40%** (177 `_xzm_xzone_malloc_freelist_outlined`), shared-cache find 12.41% plus `valid_shared_translation` 7.74% and `memcmp` 6.83%, decode+emit **1.36%**. `sample(1)` attached to `caffeinate` and is not useful.

The leftover malloc after 0011–0013 is mostly per-block `JitCompiler` construction and vector growth; the leftover memmove is geometric `words_` growth plus `store_block` / packed-publish copies.

`patches/0021-jit-compile-reuse` keeps one heap `JitCompiler` per executor and resets / reserves its emit buffers across blocks. `compiler_` is at the **end** of `Implementation`. An earlier side-link that inserted it between the arenas and `Tlb` mixed layouts with official objects and panicked `/init` (`Darwin: fatal guest event -1 at ip 0x400444`, `exitcode=0x0000000b`). Moving the member to the end fixed the boot.

Alloc SIGPROF **9:42:18–9:42:25 AM ET**, compile-cold wall **2.13 s**, 1247 delta samples: malloc samples 177→119, memmove samples 814→669. Malloc's *share* stayed ~10% and memmove's share rose because shared-cache find/memcmp also dropped; the remaining memmove is still the copy into the code cache (emit-in-place was not landed).

### CPU benches (persist off, profilers off, mem=2G ncpus=8)

Official-c134a87 launched **9:24:57 AM ET**, `BENCH_DONE` ~**9:25:45 AM ET**. Alloc (`uml-darwin-alloc`, inode 245395686 after the ABI-safe relink, 54,325,344 bytes) launched **9:40:45 AM ET**, `BENCH_DONE` ~**9:41:34 AM ET**.

| Bench | Official-c134a87 (9:24 AM ET) | Alloc reuse (9:40 AM ET) |
| --- | --- | --- |
| sh_loop_ash | 0.19 s | 0.18 s |
| sh_loop_dash | 0.18 s | 0.22 s |
| sha256_32m | 0.36 s | 0.35 s |
| apk_add_offline | 2.98 s | 2.96 s |
| evp aes-256-cbc 16 KiB | 1011520.85k (~1011.5 MB/s) | 1015584.09k (~1015.6 MB/s) |
| evp sha256 16 KiB | 1431665.70k (~1431.7 MB/s) | 1516314.54k (~1516.3 MB/s) |
| compile_tiny_sha cold | **2.45 s** | **2.15 s** |
| compile_tiny_sha warm | 1.30 s | 1.30 s |
| compile_native_loop | 0.27 s | 0.29 s |
| native_loop | 0.49 s | 0.52 s |

Compile-cold is a **12%** wall-time cut (2.45→2.15 s). Warm compile is unchanged. evp/sha/apk stay in noise except sha256 16 KiB, which was slightly up.

### Firefox TTP (same method as the 8:50 AM A/B table, persist off)

labwc image `/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-desktop-labwc.ext4`, native Metal 1920×1080, `mem=4G ncpus=8`, `UML_JIT_CACHE_BUDGET=8G` / `--jit-cache-budget=8G`, e10s on, `start-desktop-labwc-persist.sh`, shots from a machine-targeted shell (`screencapture -x -l WID`). Chrome / first body / full page times are seconds after process start. Zero `JIT_PERSIST_STATS` lines on both runs.

| Config | Window (ET) | READY | Isolated (`from_ready`) | Chrome | First English body | Full multilingual body |
| --- | --- | --- | --- | --- | --- | --- |
| Pre-0020 `uml-darwin-arena` 8G, persist off | 8:50:36–8:52:35 AM | **3.98 s** at 8:50:41 AM | **15.07 s** | **21 s** (8:51:02 AM) | **38 s** (8:51:19 AM) | **45 s** (8:51:26 AM) |
| Hook-fix `uml-darwin-hookfix` 8G, persist off | 8:58:51–9:00:50 AM | **3.36 s** at 8:58:57 AM | **14.65 s** | **26 s** New Tab (8:59:17 AM); example.com empty at 8:59:25 AM | **41 s** (8:59:32 AM) | **48 s** (8:59:39 AM) |
| Official-c134a87 8G, persist off | 9:28:12–9:30:19 AM | **4.59 s** at 9:28:17 AM | **15.68 s** | **27 s** example.com empty (9:28:39 AM) | **46 s** (9:28:58 AM) | **53 s** (9:29:05 AM) |
| Alloc reuse `uml-darwin-alloc` 8G, persist off | 9:42:38–9:44:38 AM | **3.51 s** at 9:42:42 AM | **14.03 s** | **27 s** example.com empty, “Waiting for example.com…” (9:43:05 AM) | **29 s** (9:43:07 AM) | **39 s** (9:43:17 AM) |

Official shots: `~/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-ab-official8g-manual/` (`t-092839`, `t-092858`, `t-092905`). Alloc shots: `persist-ttp-ab-alloc8g-manual/` (`t-094305`, `t-094307`, `t-094317`). Session logs: `session-ab-official8g-20261113-092812.log`, `session-ab-alloc8g-20261113-094238.log`. Official benches: `notes/jit-baseline/compile-alloc/benches-official-c134a87-20261113-092457.log`. Alloc benches: `benches-alloc-20261113-094045.log`.

Full multilingual page **53 s→39 s** (~26%) and first English body **46 s→29 s** are the Firefox win. Isolated 15.68→14.03 s and READY 4.59→3.51 s move the same direction. Chrome first-visible stayed 27 s (gap after the black READY frame is the same 1 s watcher limitation as official).

### Designed-for-iPad and Simulator

Not rebuilt or re-measured in this pass. The first side-link had to be thrown out after the `/init` ABI panic, and the uml-darwin official vs alloc A/B finished at **9:44 AM ET**. The patch is the iOS-applicable compiler-reuse series (`apply.py` after 0020). Persist must stay off on Designed-for-iPad until the openssl 8192-byte hang is shown safe. Do not install anything on a phone.

## Emit-in-place wrap-up, 0021 device/sim numbers, and persist-cache diagnosis (13 Nov 2026, 9:51 AM–10:36 AM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3. Work stayed on this host. Nothing was installed on a phone. Display resolution, voxl, Screen Sharing, Keychain, and the official 4K frozen copies (`uml-darwin-official-c134a87` / `uml-darwin-official-20261113`, md5 `91afb4a7fc3037c87b782081029fac21`) were not overwritten. Persist stayed **off** for every new measurement in this stretch. David’s 10:33 AM ET priority change: wrap up emit()/sh-loop quickly (land nothing that is not a clear win), then treat a persistent translation cache that actually speeds a second browser launch as the lever (run-2 full page target <10 s), and include Chromium alongside Firefox in those run1/run2 TTPs.

### Designed-for-iPad and Simulator, patch 0021 (done 9:51–10:15 AM ET)

Rebuilt from main `45875be` (compiler reuse). D4iPad: debugger JIT via lldb `jit_serve`, 2 GiB cache / 128 MiB L1, Aqua `gui/501` LaunchAgent, persist off, `vm.swapusage` 0, TEST SUCCEEDED, RSS peak 5.45 GiB. Simulator: Peek iPhone 17, `xcodebuild test` with `-parallel-testing-enabled NO` and one destination (a first attempt with default parallel testing spawned 3 XCTest clones and blew swap; that run was aborted). iPad (A16) was left Shutdown.

| Event | 7:50 AM D4iPad 2G (pre-0021) | 0021 D4iPad 2G (9:51–9:55 AM ET) | Sim ~80 s baseline | 0021 Sim (10:11:43–10:14:59 AM ET) |
| --- | --- | --- | --- | --- |
| READY | 3.04 s | **2.82 s** | | **4.39 s** (was 6.55 s on the earlier sim path) |
| Chrome (New Tab) | 31 s | **28 s** | | **28 s** |
| First English body | ~70 s (context) | **60 s** | | **64 s** |
| Full multilingual + icon | 70 s | **65 s** | ~80 s | **72 s** |
| sha256 32 MiB | 0.64 s | **0.48 s** | | 0.51 s |
| evp aes-256-cbc 16 KiB | 701.5 MB/s | 771.3 MB/s | | 802.4 MB/s |
| evp sha256 16 KiB | 708.5 MB/s | 773.1 MB/s | | 1039.3 MB/s |
| sh_loop_ash 20k | 0.68 s | **1.00 s (regressed)** | | 1.01 s |

D4iPad Firefox is still far from uml-darwin. The sh_loop 0.68→1.00 s regression is real on that debugger-JIT / 4G path; uml-darwin 2G minimal stayed 0.18 s, so this was not investigated further after the 10:33 AM pivot. Simulator 1G / default 256 MiB L1 shared cache thrashed (`matches=135`, `misses=135358`). The 72 s sim full-page number may be slightly conservative: leftover swap from the aborted 3-clone run was still present.

### Patch 0022 emit-in-place: measured, not landed

`patches/0022` was implemented in the local Kernarium tree only (not committed, not pushed, not on `linux-ios-fast` main). `ExecutableArena::reserve_emit` writes into the writable alias; `store_block` skips the memcpy when the emit buffer is already there; packed-publish still memcpy’s host words into the share template (needed so the template outlives L1 and zeros reloc cells). New fields only at the **end** of `ExecutableArena` / `Arm64Emitter`. `Implementation::compile_into_arena` is a method (no mid-struct insertion). `/init` did not panic.

Working `uml-darwin` was overwritten by this side-link as expected; official named copies were not. Frozen side binaries: `uml-darwin-inplace-20261113` / `uml-darwin-inplace-20261113-102031`, md5 `c3c61b7012f744e69a7af55f33769efc`.

SIGPROF compile-cold (persist off, mem=2G ncpus=8): official 2.28 s, alloc 2.13 s, inplace **2.16 s**. `_platform_memmove` samples 2211 / 2033 / **1433**. `Arm64Emitter::emit()` became 15.8% of inplace samples (per-instruction bounds/branch). Incremental emit() tightening was started and then dropped after the 10:33 AM pivot; it is not enough to change time-to-page.

After leftovers were gone, swap used sat around 1.63 GiB and would not drain to 0 without a reboot (David forbade a reboot and quitting his apps). Remeasures used “no new swap pressure”: used stayed flat or fell slightly. This is **not** literal 0 swap.

CPU benches at that flat sticky swap (used 1634.25 MiB throughout, 10:27–10:29 AM ET), persist off, mem=2G ncpus=8:

| Bench | Alloc 0021 (10:27 AM ET) | Inplace 0022 (10:28 AM ET) |
| --- | --- | --- |
| sh_loop_ash | 0.18 s | 0.18 s hold |
| sh_loop_dash | 0.19 s | 0.19 s hold |
| sha256_32m | 0.35 s | 0.36 s hold |
| evp aes-256-cbc 16 KiB | 969.0 MB/s | 944.8 MB/s slight regress |
| evp sha256 16 KiB | 1502.2 MB/s | 1527.2 MB/s slight improve |
| compile_tiny_sha cold | 2.14 s | 2.19 s slight regress |
| compile_tiny_sha warm | 1.31 s | 1.40 s regress |

Firefox TTP, same method as the 8:50 AM A/B table (labwc image, native Metal 1920×1080, mem=4G ncpus=8, 8G JIT budget, persist off), seconds after process start:

| Config | Window (ET) | READY | Chrome | First English body | Full multilingual body | Swap |
| --- | --- | --- | --- | --- | --- | --- |
| Alloc reuse, morning 0-swap (from the 9:22 AM section) | 9:42:38–9:44:38 AM | 3.51 s | 27 s | **29 s** | **39 s** | 0.00M used |
| Inplace 0022, leftover-swap (not a landing run) | t0 10:21:47 AM | 3.26 s | 20 s | **34 s** | 39 s hold | ~1.7G used, contaminated |
| Alloc reuse, flat sticky swap | t0 10:31:41 AM | **2.61 s** | **16 s** (10:31:57 New Tab) | **23 s** (10:32:04) | **31 s** (10:32:12) | used 1634→1626 MiB, no new pressure |

The 10:31 AM alloc run is the same-session baseline for any later inplace comparison. Inplace Firefox at that same flat-swap condition was **not** started; the 10:33 AM pivot landed first. Official md5 was still `91afb4a7…` after these runs.

**Landing decision: 0022 is not a clear win and is not on main.** compile_tiny_sha and evp AES do not beat alloc; the only inplace Firefox first-English number is the leftover-swap 29→34 s regression. The 39 s full-page headline is not going to be solved by trimming `emit()`.

### Why patch 0020’s persistent cache had no Firefox win

Numbers already in the 8:15–8:19 AM ET rows of the persist A/B table: persist-on cold full page **63 s**, warm **46 s**, vs persist-off hook-fix **48 s** and pre-0020 arena **45 s**. READY was **4.62 s cold / 4.66 s warm** — no boot win either. Persist-on cold paid a real I/O tax (Isolated 18→23 s, full 48→63 s).

This is not primarily “ASLR / guest-VA keying.” The on-disk key is already `(page_hash of the 4 KiB guest code page, codegen profile hash, page offset)` plus an optional source-image fingerprint (ext4 UUID / size / mtime). `rejected=0` on both the cold and warm runs: when a key is found, guest-byte validation and CRC pass. Process-lifetime `code_page_identity` is used only for the in-RAM location index, as designed.

The coverage math, from `session-persist-cold-20261113-081534.log` and `session-persist-warm-20261113-081750.log`:

| Point | Cold persist-on (8:15:34–8:17:12 AM ET) | Warm persist-on (8:17:50–8:19:27 AM ET) |
| --- | --- | --- |
| READY | misses 149,998 / insertions 164,159 / stores 20,480 / hits 18,534 | misses 138,642 / insertions 174,808 / stores 10 / hits 41,338 |
| End of ~100 s window | misses 1,339,379 / insertions 1,496,849 / stores **147,480** / hits 179,445 | misses 1,233,479 / insertions 1,533,890 / stores +10,340 / hits **320,315** |

Cold persisted only **147,480 / 1,496,849 ≈ 9.8%** of admitted translations. Warm then found those stored entries (`hits=320,315`, `rejected=0`, cache only grew 147,456→157,796). Unique misses fell by only ~106k (~8%). That is why run 2 cannot be “a few seconds.” An earlier aborted warm start (`session-persist-warm-20261113-081315.log`, 3 s, hits=1) opened a previous **413,696-entry / 751 MB** `data.jtc`; the cache later used for the real warm run was the 58 MB file from the 8:15 cold run (now 60M + 7.7M index under `/Volumes/KernariumCS/jit-cache/uml-darwin`).

`remember()` silently returns, with **no counter**, when it sees a leftover host pointer in `[0x100000000, 0x200000000)` after zeroing recorded reloc cells. That range is typical macOS user/JIT VAs. The pointers are real: `Arm64Emitter::call()` / `call_transition()` / `call_preserving_flags()` use `load_stable_pointer()` → `load_literal_constant()` and bake the helper address into the literal pool **without a `JitRelocation`**. Only `direct_link` / `indirect_link` / `guest_pc` are recorded today, so any block that calls a host helper is dropped from the durable store. The ~10% that are stored (pure ALU-style translations without helpers) do hit on run 2; they are not enough of Firefox’s compile working set to move TTP.

Other costs, once a block *is* stored: every persist-on `find`/`publish` fetches and wyhashes a 4 KiB guest page (`persistent_identity_for`); every hit `pread`s the record, CRC32s it, memcpy’s into a packed `SharedTranslation`, inserts into the RAM cache, then copies again into L1 and applies relocs. `remember()` fsyncs and rewrites the whole `index.jtc` every 4,096 stores under the persist mutex (cold: ~147k stores ≈ 36 full index syncs). There is no mmap of `data.jtc`. Lookup cost plus that I/O tax is consistent with persist-on cold being *slower* than persist-off, and with warm tying persist-off rather than beating it.

Designed-for-iPad openssl `aes-256-cbc` 8192-byte hang (persist-on only, 8:37–8:43 AM ET, ~0.3% CPU until SIGTERM) is still unexplained by a rerun, but the same leftover-pointer window is a plausible cause: it is shaped like uml-darwin macOS VAs and may **admit** a Designed-for-iPad translation that still contains a host pointer outside that range, which then jumps into the previous process after reload — or `remember()` fsync/index rewrite under the mutex during heavy eviction can stall the guest. Persist stays opt-in and must not be turned on for D4iPad until this path is shown safe.

### Persist redesign (to implement; stays opt-in until proven)

Success: Firefox (and Chromium, same page, same method) run 1 ~ current persist-off TTP; run 2 full page dramatically lower, target **<10 s**. CPU benches no regression. Only then consider default-on.

1. **Coverage is the first lever.** Add `JitRelocationKind::host_callable`. `call()` / `call_transition()` / `call_preserving_flags()` (and `load_stable_pointer` used for host functions) must record a reloc whose key is a durable image identity plus offset (`dladdr` / Mach-O slide), not a process-local host VA. Materialize patches the current process’s address. `remember()` classifies any leftover host pointer the same way instead of silently dropping the block; unclassifiable pointers are refused with a **logged counter** (`leftover_host`, `foreign_image`, `reloc_oob`, `already_present`, `no_identity`) and are never stored as raw VAs. This also closes the D4iPad “wrong VA window” hole: stop using a hardcoded `[0x1_0000_0000, 0x2_0000_0000)` test.
2. **Lazy link** is already the packed-publish rule (reloc cells zero in the template). Keep it: persist the unlinked form, link on first materialize in the new process.
3. **Map `data.jtc` (mmap)** and return views into the mapping instead of `pread` + CRC + memcpy on every hit. CRC at write / flush / open, not on the hit path. Defer `fsync` and the index rewrite to a background / exit flush, not every 4,096 stores under the mutex.
4. **Key by file + offset** when the guest page is file-backed (backing inode / generation / mtime + file offset + page offset), and only fall back to a content hash for anonymous / JIT pages. Content hashing is already ASLR-stable for PIC text (warm did not balloon the cache with new hashes), so this is a lookup-cost and dirty-page-stability win, not the coverage fix. `CodePageStamp` today is only a process-lifetime identity/version; a backing-file API still has to be added.
5. **Cap** the durable store so it cannot grow to the earlier 751 MB / 413k-entry file. Keep source-fingerprint invalidation.
6. Stay **opt-in** (`UML_JIT_PERSISTENT_CACHE` / `KERNARIUM_JIT_PERSISTENT_CACHE`) until run 2 meets the target, D4iPad 8192 is shown safe, and CPU benches hold.

### Fast baseline / tiered JIT for first launch (sketch only; not built)

Run 1 will still compile on the order of a million unique blocks even after persist works (that is the fill of the cache). Incremental emit() trims will not make a cold Firefox/Chromium page fast. A later first-launch path should be a cheap baseline tier in front of the current optimizing JIT: decode once and emit a thin template / threaded-code body (or reuse the existing gadget engine as that tier) so the first execution of a block is cheap, then promote hot blocks to today’s compiler and persist the optimized form (baseline only if it is also cheap to record). The success metric is cold run-1 TTP moving toward run-2 without waiting for a full optimizing compile of libxul / Chromium. Do not build this until the persist coverage path is landed and measured.

### Chromium on the labwc desktop image

David prefers Chromium. Firefox stays installed. The original 0444 `alpine-3.24.2-desktop-labwc.ext4` (03:58 AM ET) was left untouched. An APFS clone was frozen as `alpine-3.24.2-desktop-labwc-pre-chromium-20261113.ext4`. Alpine’s `chromium` package was installed into a separate writable clone, `alpine-3.24.2-desktop-labwc-chromium-20261113.ext4`, booted official-c134a87 with `UML_BOOT_UPPER=none` (so writes hit the ext4, not the production tmpfs overlay), then a clean `poweroff` (not `-f`). Journal was clean afterward; the work image was chmod 0444. Official md5 stayed `91afb4a7fc3037c87b782081029fac21`. Swap used stayed 1506.25 MiB (no new pressure).

Install window: **10:39:38–10:39:54 AM ET** (`install-chromium-labwc-20261113-103938.log`). Guest uptime at `INSTALL_CHROMIUM_DONE` was 13.80 s. Result: **Chromium 156.0.8078.79** Alpine (`chromium-156.0.8078.79-r0` plus `chromium-angle` and `chromium-common`). `/usr/bin/chromium` → `chromium-browser` → `/usr/lib/chromium/chromium-launcher.sh`. `/usr/lib/chromium/chrome-sandbox` is setuid root (`-rwsr-xr-x`). `/usr/bin/firefox` is still present. The ext4 went from whatever it was to **3.0 GiB used / 725.4 MiB free (81%)**. Scripts: `scripts/desktop-guest/install-chromium.sh`, `scripts/macos-metal/install-chromium-labwc.sh`, `scripts/macos-metal/boot.env-upper-none`.

`start-desktop-labwc.sh` and the persist overlay now honor `DESKTOP_BROWSER` / `/usr/local/etc/desktop-browser` (`firefox` default), emit `===CHROMIUM_START===`, open `https://example.com`, and prefetch `/usr/lib/chromium/*`. Extra flags come from `/usr/local/etc/chromium-flags` (overlaid from `scripts/desktop-guest/chromium-flags`). `launch-ab-uml-darwin.sh` takes optional args 5–6: `firefox|chromium` and an explicit rootfs; Chromium defaults to the new image.

### Chromium sandbox / zygote under UML, and a persist-off TTP baseline

The labwc session runs as root, same as Firefox. That is the actual zygote issue:

1. First persist-off smoke (`chromesmoke0swap8g`, t0 **10:40:39 AM ET**, no extra flags): Chromium started and immediately exited. `/tmp/chromium.log` was `ERROR:content/browser/zygote_host/zygote_host_impl_linux.cc:103] Running as root without --no-sandbox is not supported. See https://crbug.com/638180.` The process list went `chromium` → `chrome_crashpad <defunct>` → empty. The setuid `chrome-sandbox` is present but Chromium will not use a sandbox when the browser itself is root. `--no-zygote` was not required.
2. Retry with `--no-sandbox --disable-setuid-sandbox` (`chromenosandbox0swap8g`, t0 **10:41:11 AM ET**): the process stayed up and a window appeared at **10:41:34 AM ET (+23 s)**, but the page stayed on “Loading…” behind a GNOME **“Choose password for new keyring”** / Default Keyring modal, plus an infobar that `--disable-setuid-sandbox` is an unsupported flag.
3. Workaround used: **`--no-sandbox --password-store=basic`** (drop `--disable-setuid-sandbox`). `--no-sandbox` is required as root; `--password-store=basic` uses Chromium’s built-in store so gnome-keyring never prompts. The `--no-sandbox` unsupported-flag infobar remains (it cannot be avoided if we have to pass that flag). The only other log line was `vaInitialize failed: unknown libva error` (VA-API is not on this Zink/KosmicKrisp path; it did not block painting).

Persist-off Chromium TTP, same method as the Firefox A/B table, alloc reuse `uml-darwin-alloc`, 8G JIT budget, native Metal 1920×1080, mem=4G ncpus=8, new chromium labwc image, sticky swap used 1506.25 MiB with no new pressure, t0 **10:42:44 AM ET** (`session-ab-chromebasic0swap8g-20261113-104244.log`, shots `persist-ttp-ab-chromebasic0swap8g-manual/`):

| Event | Time (ET) | Seconds after process start |
| --- | --- | --- |
| READY | 10:42:47 AM (guest uptime 2.57 s) | **3 s** |
| Chrome (window + `example.com` URL, tab still “Loading…”, blank body, `--no-sandbox` infobar) | 10:43:03 AM (`t-104303`) | **19 s** |
| First English body **and** full multilingual + book icon (Example Domain, Arabic/French/Russian/Spanish, Learn more) | 10:43:04 AM (`t-104304`) | **20 s** |

English body and the full multilingual page landed in the same 1-second watcher tick. Compare the same-session Firefox alloc baseline at flat sticky swap (t0 10:31:41 AM ET): chrome **16 s**, first English **23 s**, full multilingual **31 s**. This Chromium figure is a single persist-off run, not yet a persist run1/run2 pair; the window is the default first-run size (not maximized) and shows the `--no-sandbox` infobar. Persist run1/run2 for **both** Firefox and Chromium still waits on the redesigned cache (coverage / `host_callable` relocs first) and stays opt-in until that path is shown safe, including the D4iPad openssl 8192 hang.



### SIGPROF of Firefox TTP (13 Nov, persist-v2 fix4) — where the time goes

Same method as the 10:31 / 10:42 A/Bs: native Metal 1920×1080, mem=4G ncpus=8, 8G JIT budget, chromium labwc image, Firefox, `https://example.com`. Persist stayed opt-in. The fair A/B is one binary (`uml-darwin-persist-v2-20261113-fix4`, md5 `1d3441a63b548494b3f891e1c7024d04`) persist-off vs persist-on warm run2. Host SIGPROF is `ITIMER_PROF` at 999 Hz (process CPU, not wall). Blocked example.com wait is therefore undercounted and is taken from OCR (“Waiting for example.com…”). `persistent_content_hash` is reclassified into persist lookup (the analyzer had bucketed it as helpers). Chrome-window hists are usable (off unique 3337 / dropped 232; r2 unique 3733 / dropped 784); later full-run unique saturates at 4096.

| Event | Persist-off (t0 11:30:08 AM ET) | Persist-on warm run2 (t0 11:32:15 AM ET, cache `/Volumes/KernariumCS/jit-cache/persist-v2-firefox`) |
| --- | --- | --- |
| READY / FIREFOX_START | **3 s** (guest 3.28 / 3.34) | **3 s** (guest 3.58 / 3.68) |
| Isolated Web Content | 17.32 s up / 14.04 from_ready | 23.35 s up / 19.77 from_ready |
| Chrome (New Tab) | **25 s** | **42 s** |
| English + full (Example Domain) | **40 s** (waiting 32–37, transferring 39) | **69 s** (waiting 56–69, transferring 70) |
| Exit persist | (off) insertions=1,538,646 | hits=1,269,293, stores=0, cap_rejected=230,053, entries=483130, data=1,073,741,608 (1 GiB cap full) |

READY→chrome is the pre-network window that already loses. Off: wall 21 s, CPU 32.68 s (cpu/wall 1.56). R2: wall 39 s, CPU 57.22 s (cpu/wall 1.47).

| Class | Off CPU-s (pct) | R2 CPU-s (pct) | Delta |
| --- | ---: | ---: | ---: |
| translate/compile | 2.79 (8.53%) | 1.60 (2.80%) | −1.19 (persist saved compile) |
| cache lookup/materialize (as bucketed) | 3.40 (10.41%) | 5.98 (10.44%) | +2.58 |
| + `persistent_content_hash` (reclassified from helpers) | ~0 | +1.54 | +1.54 |
| executing translated code (`jit_generated`) | 1.78 (5.45%) | 2.17 (3.79%) | +0.39 |
| helpers + executor (after moving content_hash) | 0.76 (2.31%) | ~1.60 | +~0.8 |
| memcpy/alloc | 8.11 (24.83%) | 10.88 (19.01%) | +2.77 |
| syscalls / kernel IO excluding `mach_msg2` | ~1.62 | ~2.56 | +0.94 |
| `mach_msg2_trap` | 0.06 (61 samples) | **13.23** (13,218 samples, 23.12%) | **+13.17** |
| locks/sync (`__ulock_wait`/`wake`, psynch) | **13.27 (40.59%)** | 16.48 (28.80%) | +3.21 |
| display/gpu in-process | 0.65 (1.99%) | 0.57 (0.99%) | ~0 |
| total CPU | 32.68 | 57.22 | +24.5 |
| wall | 21 | 39 | +18 |

Start→full (includes network wait after chrome): off 40 s wall, CPU ≈78.8 s, locks 52%; r2 72 s wall, CPU ≈131.7 s, locks 37%, `mach_msg2` 19%. After chrome, example.com wait is ~8 s off vs ~13 s r2 (OCR).

**Is translation the dominant cost of TTP?** No. On persist-off READY→chrome, compile is only 8.53% (2.79 CPU-s) and `jit_generated` execution is 5.45% (1.78 CPU-s). The largest classes are locks/sync (40.59%) and memcpy/alloc (24.83%), then in-RAM shared-cache lookup (10.41%). Guest Isolated at 17.32 s and chrome at 25 s are Firefox bring-up, not page-body compile. A tiered baseline JIT or block chaining / inline caches is useful later, not the current bottleneck.

**Why did 1.27M persist hits leave run2 slower than off?** Persist saved compile (−1.19 CPU-s) but added much more than it saved before New Tab appears (42 s vs 25 s). The extra ~24.5 CPU-s / 18 s wall in READY→chrome is: `mach_msg2_trap` +13.17 CPU-s (run2-only; consistent with file-backed mmap page-ins of the 1 GiB `data.jtc` on KernariumCS via the Mach pager); persist lookup + 4 KiB content hash +~4.0 CPU-s; locks +3.21; memcpy/alloc +2.77. cpu/wall is similar (1.47 vs 1.56), so run2 is not idle-waiting more in that window — it does more CPU work, then also waits longer on example.com. Looking up a stored translation from a cold mmap can cost more than recompiling.

Top r2 READY→chrome symbols: `mach_msg2_trap` 13,218; `_platform_memmove` 5,951; `__ulock_wait` 5,311; `__ulock_wake` 4,549; `PersistentTranslationStore::lookup` 2,473; `jit_generated` 2,165; `persistent_content_hash` 1,534; shared find 1,201; `valid_shared_translation` 1,135. Off top: `__ulock_wait` 5,072; `__ulock_wake` 3,676; memmove 3,650; `Arm64Emitter::emit` 1,788; `jit_generated` 1,780; `SharedTranslationCache::find` 1,375.

### Ranked plan for a full page under ~10 s

1. **Make persist lookup cheaper than compile, or run2 cannot win.** The clear reason run2 is slower than off is the hit path: do not fault 1 GiB of `data.jtc` off KernariumCS on the TTP path (RAM-resident or a cache that does not share a volume with the guest rootfs), cache/elide the per-find 4 KiB `persistent_content_hash`, and raise the cap so Firefox UI translations actually stay stored. A 1 GiB cap overflowed in one cold Firefox session (`cap_rejected=230,053`).
2. **Cut `__ulock_wait` / psynch contention** — the largest class on persist-off TTP (13.27 CPU-s in the 21 s chrome window). This is a first-launch win even with persist off, and is the top item for “off is already 25/40 vs <10 s.”
3. **Cut memcpy/alloc of translations** (~25% of off READY→chrome).
4. **Async/batched `remember()`** so run1 READY stays ~3 s (cold labwc socket was 12.7 s when remember/leftover-scan ran on the boot path).
5. example.com wait is 8–13 s after chrome; a local/prefetched page would help measured TTP but is a methodology change.
6. Tiered baseline JIT / block chaining / inline caches: compile 8.5% and `jit_generated` 5.5% — later, not the current bottleneck.

### Follow-on implementation (not landed)

0022 emit-in-place is disabled on the persist source (`compile_into_arena` is a passthrough so A/Bs isolate persist). Official `uml-darwin-official-c134a87` / `-20261113` md5 `91afb4a7fc3037c87b782081029fac21` inode 245391030 and alloc `uml-darwin-alloc` md5 `848b59fb6531ed6fa224e3973625c98a` inode 245395686 were not overwritten.

What was tried, all as named side binaries, persist still opt-in:

- Default cap 1 GiB → 4 GiB, used-size mmap (64 MiB aligned, grow on demand) so a 4 GiB `MAP_SHARED` is not taken at open.
- In-process RAM prefetch of `data.jtc`, then a paced background-QoS prefetch, then prefetch disabled: a tight 1 GiB memcpy off KernariumCS during guest boot left READY at ~29–33 s (`seatd` 17–18 s vs ~2 s) and the Metal window stuck on the “Darwin UML Virtio-Gpu” console (no Isolated, no New Tab). Staging the same cache to `/var/tmp/persist-v2-firefox-local` (internal SSD, rsync --sparse 19.4 s *before* t0) did not restore READY once the new hit/store path was in the binary.
- Async/batched `remember()` (writer thread + inflight) and a thread-local page-hash cache (including a later “only cache successful hashes” fix).

**Bisect:** the same local cache, `uml-darwin-persist-v2-20261113-fix4`, READY **3.85 s**, Isolated 26.00 s, chrome **48 s**, English+full **73 s** (t0 11:57:54 AM ET; waiting 11:58:56, body 11:59:07). Exit: hits=1,304,101, stores=0, cap_rejected=220,019. The new binaries on that same cache stay at READY ~30 s: at `seatd`, both have ~54k persist hits, but fix4 reaches that at **1.95 s** and fix9/fix10 only at **~18 s**. The hit path is about 10× slower even after lookup/remember were put back on the simple fix4 shape (sync memcpy, no writer, no hash cache, cap-1G recheck still 32.8 s READY). That is not a clear win; it is not landed or pushed. The 10× regression vs fix4 on an otherwise identical cache is still unexplained at the symbol level and needs its own SIGPROF of fix10 vs fix4 before any further persist store changes.

fix5 persist-off (0022 removed, t0 11:39:46 AM ET) held vs the 11:30 off baseline: READY 3.10 s, Isolated 14.92 s, chrome **21–22 s** (11:40:07), English+full **37–38 s** (11:40:23). That only confirms 0022-off did not regress persist-off TTP; it is not a persist win.

Swap during this work stayed sticky (~1.3–1.4 GiB used, later 1218 MiB of a 2 GiB swap file); official/alloc md5s rechecked unchanged at 12:08 PM ET. A stale 4 GiB-cap copy of the Firefox persist cache is still at `/var/tmp/persist-v2-firefox-local` (~1.1 GiB allocated) on the internal Data volume (95% full); the KernariumCS copy is `/Volumes/KernariumCS/jit-cache/persist-v2-firefox`. Neither was emptied.

D4iPad openssl 8192 persist-on, persist-on benches, and Chromium persist-on were not rerun and remain outstanding before any later land.


## Exclusive-phase removal (0022, 13 Nov 2026, 2:18–2:46 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3. Work stayed on this host. Nothing was installed on a phone. Display resolution, voxl, Screen Sharing, and Keychain were not changed. Persist stayed **off**. Official frozen 4K copies `uml-darwin-official-c134a87` / `-20261113` (inode 245391030 / 245391031, md5 `91afb4a7fc3037c87b782081029fac21`) were not overwritten.

This official 0022 is the exclusive-scope removal, not the earlier emit-in-place experiment (that work was measured and not landed; it never shipped on main).

### Preflight

Start-of-run preflight no longer refuses on stale swap used (~1.2G leftover after the dirty 0022-cas SIGPROF blowup, with no active paging). It now requires reclaimable headroom (`vm_stat` free + speculative + inactive + purgeable) ≥ guest mem + ~2G margin, and a quiet swap-out rate (≤16 pages in a 2 s sample). Overlap refusal stays. Mid-run SWAP_ABORT is relative to swap used at start (+2048M). `UML_ALLOW_HEAVY=1` still overrides.

### Clean tree

Worktree `Kernarium-0022-clean` from `ce0fa86` + official 0001–0021 (`ee2e467`) + this three-file change (`9676ead`). `git diff ee2e467` is only `jit_semantic_memory.cpp`, `a32_execute.cpp`, and `jit_publication.hpp` (+30/−10). No persist-v2, no `user_map.hpp`, no lockfix, no enhanced SIGPROF (official 0008, 9526 B, default off, is in the 0021 base).

Binary `uml-darwin-0022-clean-20261113` / `uml-darwin-official-0022-20261113`, built 1:52:09 PM ET, md5 `6ea8180e05fc6736d32530811ba3c439`, 54,302,536 bytes, kernel local2. Promoted to live `uml-darwin` at 2:46:31 PM ET. Alloc (0021) `uml-darwin-alloc` md5 `848b59fb6531ed6fa224e3973625c98a` is unchanged.

### Unit tests (macos-unit exclusive suites, 1:50:27–1:51:08 PM ET)

`reservation_alias` (line 57, exit 134) and `exclusive_events` (exit reason 0x7 / floating_point_trap) fail on clean 0021 (`ee2e467`, scope still on) and fail the same way after `9676ead`. exclusive_completion, publication_gate, exclusive_progress, and jit_a32_exclusive PASS on both. The two failures are pre-existing on 45875be/0021, not a regression.

### CPU benches vs alloc (mem=2G ncpus=8, persist off, 2:20:08–2:21:47 PM ET)

Preflight: headroom 7678M / 8380M, need 4096M, swapouts_delta=0, free% 82. Both status=0. Swap used stayed 1238.75M (delta 0). Peak RSS alloc 2239 MiB, clean 2072 MiB. No SWAP_ABORT.

| Bench | Alloc (2:20:08 PM ET) | 0022-clean (2:20:58 PM ET) |
| --- | --- | --- |
| compile_tiny_sha cold | 2.06 s | **2.00 s** (−2.9%) |
| compile_tiny_sha warm | 1.29 s | 1.32 s (+2.3%) |
| compile_native_loop | 0.24 s | 0.27 s (+30 ms) |
| native_loop | 0.51 s | 0.58 s |
| sha256_32m | 0.36 s | 0.38 s |
| apk_add_offline | 2.98 s | 3.06 s |

Compile holds within noise. `compile_tiny_sha` is the canary that missed on the dirty persist-v2 tree (+35% / +95% warm); here it holds. `compile_native_loop` +30 ms is inside today's alloc noise (earlier alloc0 was 0.28 s).

Logs: `notes/jit-baseline/compile-alloc/benches-alloc-c22ab-20261113-142006.log`, `benches-clean-c22ab-20261113-142056.log`.

### Guest atomic-stress (8 threads × 200k, mem=2G, 2:22:50–2:24:32 PM ET)

Both **PASS**, `atomics=1`. Swap delta 0. Peak RSS alloc 1804 MiB, clean 1834 MiB. Clean's wall clock was shorter because apk had already populated the shared minimal image on the alloc run; the result that matters is PASS.

### Firefox + Chromium TTP, ABAB, 0 new swap (2:25:29–2:41:18 PM ET)

Same chromium labwc image for both browsers (`alpine-3.24.2-desktop-labwc-chromium-20261113.ext4`), native Metal 1920×1080, `mem=4G ncpus=8`, `--jit-cache-budget=8G`, persist off. Times are seconds after process start. Chrome is the first visible browser window after the empty labwc desktop (New Tab, Loading, or example.com tab). Boot-console OCR hits of “chromium” on the 865k kernel dmesg frames are ignored. English is first “This domain is for use”. Full is Example Domain title + body; Learn more is noted when later. Network is English − chrome.

No run grew swap (delta 0 the whole ABAB). Stale used fell 1230.75M → 1014.75M by 2:45 PM. Clean peak RSS stayed in the alloc band (5185–5224 MiB vs alloc 4946–5584 MiB). The 12.3G dirty-tree / 6.4G casex leak did not reappear. No SWAP_ABORT.

| Run | Window (ET) | READY | Chrome | English | Full (title+body) | Learn more | Net | Peak RSS | Δ swap |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Firefox alloc r1 | 2:25:29–2:27:21 PM | 4 s | 21 s example.com/ (window 19 s) | 24 s | 25 s | 30 s | 3 s | 5110 MiB | 0 |
| Firefox 0022 r1 | 2:27:27–2:29:19 PM | 2 s | **16 s** New Tab | **19 s** | **19 s** | 20 s | 3 s | 5189 MiB | 0 |
| Firefox alloc r2 | 2:29:24–2:31:16 PM | 3 s | 18 s New Tab | 22 s | 31 s | 32 s | 4 s | 5584 MiB | 0 |
| Firefox 0022 r2 | 2:31:22–2:33:14 PM | 3 s | **16 s** example.com/ | **17 s** | **19 s** | 20 s | 1 s | 5185 MiB | 0 |
| Chromium alloc r1 | 2:33:32–2:35:24 PM | 2 s | 18 s Loading | 20 s | 20 s | 20 s | 2 s | 4946 MiB | 0 |
| Chromium 0022 r1 | 2:35:30–2:37:22 PM | 2 s | **15 s** Example Domain | **16 s** | **16 s** | 16 s | 1 s | 5224 MiB | 0 |
| Chromium alloc r2 | 2:37:27–2:39:20 PM | 3 s | 18 s Loading | 20 s | 20 s | 20 s | 2 s | 5495 MiB | 0 |
| Chromium 0022 r2 | 2:39:25–2:41:18 PM | 3 s | **14 s** Loading | **17 s** | **17 s** | 17 s | 3 s | 5176 MiB | 0 |

Firefox chrome mean 19.5 s → **16 s**, English 23 s → **18 s**, full 28 s → **19 s**. Chromium chrome 18 s → **14.5 s**, English/full 20 s → **16.5 s**. READY is unchanged (~2–4 s). This is a clear TTP win at sane memory.

Shots: `~/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-ab-c22-{ff,cr}-{alloc,clean}-{1,2}-manual/`. Session logs: `session-ab-c22-*-20261113-*.log`.

### Landing

Landing bar met: compile within noise, TTP better, memory sane, unit tests no worse than base. Frozen copy already existed; new official named copy `uml-darwin-official-0022-20261113` (inode 245630846); live `uml-darwin` promoted at 2:46:31 PM ET; old official copies left frozen. Patch: `patches/0022-jit-exclusive-host-cas`.


## Designed-for-iPad and Simulator, official 0022 (13 Nov 2026, 2:48–3:46 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host: Mac mini (M2 Pro, 16 GB), macOS Tahoe 26.7.3. Built from the clean worktree `Kernarium-0022-clean` (`ee2e467` + `9676ead`), not the dirty persist-v2 `src/Kernarium`. Persist stayed **off**. Nothing was installed on a phone. iPad (A16) stayed Shutdown. Display resolution, voxl, Screen Sharing, and Keychain were not changed. Official `uml-darwin` 0022 (md5 `6ea8180e05fc6736d32530811ba3c439`) was not overwritten.

Kernel for these iOS builds is local2 (`6.18.60-g8246678b2d74`). Guest: 1920×1080, mem=4G, 8 vCPUs. Page is still `https://example.com`. TTP below is **seconds after DESKTOP_READY**, the same method as the published 0021 D4iPad/Sim table (chrome = first real window after the empty labwc desktop; English = “This domain is for use”; full = Example Domain title + body; Learn more noted when OCR’d). Boot-console OCR hits of “chromium” are ignored.

### Build overlays (local, not pushed to Kernarium)

The clean 0022 tree needed the same bakeoff overlays official 0014 / 0021 D4iPad used, copied in rather than taken from persist-v2: `darwin/memory/CMakeLists.txt` lists `mmu/user_map.cpp`; official 0014 `user_map.hpp` (37-line API header, no persist markers); Signing.xcconfig + gitignored Signing.local.xcconfig (team `4P2629648N`, bundle `com.davidhope.kernarium`) and pbxproj `PRODUCT_BUNDLE_IDENTIFIER=$(KERNARIUM_BUNDLE_IDENTIFIER)`; ContentView.swift honors `KERNARIUM_DISPLAY_WIDTH/HEIGHT` (1920×1080); `KernariumRuntime.mm` honors `KERNARIUM_JIT_EXECUTOR_CACHE_BUDGET` / `UML_JIT_EXECUTOR_CACHE_BUDGET` and passes `--jit-executor-cache-budget=`. D4iPad: Aqua `gui/501` LaunchAgent + lldb `jit_serve` one-shot prepare (2 GiB cache / 128 MiB executor). Simulator: `CODE_SIGNING_ALLOWED=NO`, Peek iPhone 17 (`8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB`), `-parallel-testing-enabled NO`, one destination, default 1 GiB cache / 256 MiB executor (same as 0021 Sim).

Scripts (repointed at `Kernarium-0022-clean`): `scripts/macos-metal/build-d4ipad-0022.sh`, `build-sim-0022.sh`, `launch-d4ipad-0022.sh`, `bootstrap-d4ipad-0022.sh`, `com.davidhope.d4ipad-0022.plist`, `watch-d4ipad-0022-shots.sh`, `watch-sim-0022-shots.sh`, `launch-sim-0022-test.sh`. `package-ios-linux-device-and-simulator.sh` is `ROOT_DIR`-overridable (build scripts export `ROOT_DIR` to the clean tree; the default is still the dirty checkout). Mid-run SWAP_ABORT in `launch-sim-0022-test.sh` stays on even when `UML_ALLOW_HEAVY=1` is used to pass start-of-run preflight. Do not weaken `preflight-uml-darwin.sh` for uml-darwin. The 4G+2G headroom gate cannot pass on this 16 GB mini once Peek is Booted (~12 GiB RSS); Simulator runs used `UML_ALLOW_HEAVY=1` for start only.

### Chromium work image

uml-darwin always injects `start-desktop-labwc-persist.sh` via `--guest-file`. D4iPad/Sim have no guest-file injection, so the official installer image `alpine-3.24.2-desktop-labwc-chromium-20261113.ext4` runs `INSTALL_CHROMIUM` and poweroffs (ready=false). A baked work copy, `alpine-3.24.2-desktop-labwc-chromium-d4ipad-20261113.ext4`, has the real 7840-byte labwc `start-desktop.sh`, `desktop-browser=chromium`, and chromium-flags. After `switch_root`, guest-files live under `/usr/local/bin`, not `/payload`. Official 0022 was used only as a named copy for that fixup; live `uml-darwin` was not overwritten.

### Designed-for-iPad

Firefox (15:06:46–15:10:07 ET, stamp `20261113-150646`, TEST SUCCEEDED, exit 0). Preflight: headroom 7288M, need 6144M, swapouts_delta=0, start_swap 934.75M. JIT attach 15:07:25, detach/boot 15:07:33, DESKTOP_READY 15:07:36 ET, guest uptime **2.69 s**. Peak RSS 6.32 GiB (0021 5.45 GiB). Peak swap 1873.56M (Δ ~+939M; SWAP_ABORT limit start+2048M, not tripped).

Chromium (15:27:06–15:29:58 ET, stamp `20261113-152706`, baked image, TEST SUCCEEDED, exit 0). READY 15:27:33 ET, uptime **4.20 s**. Peak RSS 6.62 GiB. Peak swap 1433.56M = start (Δ 0). No published 0021 D4iPad Chromium baseline. A first attempt on the official installer image (15:16:03) powered off after INSTALL_CHROMIUM and is not scored.

| Event | 0021 D4iPad FF (9:51–9:55 AM ET) | 0022 D4iPad FF (3:06–3:10 PM ET) | 0022 D4iPad CR (3:27–3:29 PM ET) |
| --- | ---: | ---: | ---: |
| READY (guest uptime) | 2.82 s | **2.69 s** | 4.20 s |
| Chrome (after READY) | 28 s size-jump | **26 s** size-jump (OCR New Tab 30 s) | 39 s Loading |
| English (after READY) | 60 s | **37 s** | **43 s** |
| Full title+body (after READY) | — | **38 s** | **43 s** |
| Learn more (after READY) | 65 s | **44 s** | not OCR’d (no-sandbox banner) |
| sh_loop | 1.00 s | **0.28 s** | **0.22 s** |
| sha256 32 MiB | 0.48 s | **0.44 s** | **0.40 s** |
| apk openssl | 5.25 s | 6.98 s | **3.02 s** |
| Peak RSS | 5.45 GiB | 6.32 GiB | 6.62 GiB |

Firefox window/page times improved clearly vs published 0021 (English 60→37, Learn more 65→44). The sh_loop 1.00 s figure on 0021 D4iPad recovered to 0.28 s. apk openssl was a bit slower on Firefox (6.98 vs 5.25); Chromium’s 3.02 s is a different image/session.

### Simulator (Peek iPhone 17)

Firefox (15:36:19–15:40:13 ET, stamp `20261113-153619`, TEST SUCCEEDED, exit 0). `UML_ALLOW_HEAVY=1` after preflight refused (headroom 6000M < 6144M with Peek already up). SWAP_ABORT stayed on; start_swap 1158.94M; peak swap = start (Δ 0). READY 15:37:36 ET, uptime **8.03 s**. Peak RSS 2.50 GiB. JIT 1G / 256M, same as 0021 Sim.

Chromium (15:42:59–15:45:48 ET, stamp `20261113-154259`, baked image, TEST SUCCEEDED, exit 0). READY 15:43:16 ET, uptime **4.77 s**. Peak RSS 2.79 GiB. start_swap 1134.94M, Δ 0. No SWAP_ABORT. Peek was shut down at 15:46:51 ET after the run.

| Event | 0021 Sim FF (10:11:43–10:14:59 AM ET) | 0022 Sim FF (3:36–3:40 PM ET) | 0022 Sim CR (3:42–3:45 PM ET) |
| --- | ---: | ---: | ---: |
| READY (guest uptime) | 4.39 s | 8.03 s | 4.77 s |
| Chrome (after READY) | 28 s | 34 s size-jump (OCR 40 s) | **27 s** Loading |
| English (after READY) | 64 s | **55 s** | **37 s** |
| Full title+body (after READY) | — | **55 s** | **37 s** |
| Learn more (after READY) | 72 s | not OCR’d (iPhone-sim crop of 1920×1080) | not OCR’d (banner + crop) |
| sh_loop | 1.01 s | **0.25 s** | **0.20 s** |
| sha256 32 MiB | 0.51 s | **0.41 s** | **0.38 s** |
| apk openssl | 4.75 s | **3.51 s** | **2.16 s** |
| Peak RSS | — | 2.50 GiB | 2.79 GiB |

Simulator Firefox English/full and all CPU benches improved vs 0021. READY 8.03 s is slower than 0021’s 4.39 s and than this session’s Chromium 4.77 s on the same booted Peek; JIT budget matched 0021, so this is more likely first-guest-after-boot / residual ~1.1G swap pressure than a 0022 codegen regression. Chrome size-jump was also a bit later (34 vs 28). Learn more never appears in these iPhone-sim screenshots (page cropped); title+body is the scored full-page time.

Logs and shots stay on the mini under `~/linux-ios-bakeoff/notes/macos-metal-desktop/` (`kernarium-{ipad,sim}-0022-*`, `persist-ttp-{d4ipad,sim}-0022-{ff,cr2,cr}-manual/`).


## Fetch-view (guest RAM host_pointer) — measured, not landed (13 Nov 2026, 3:55–4:28 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Official 0022 was the A side.
Persist off. Official `uml-darwin` / `uml-darwin-official-0022-20261113`
(md5 `6ea8180e05fc6736d32530811ba3c439`, inode 245630846) was not
overwritten. Display resolution, voxl, Screen Sharing, Keychain, and the
physical iPad were not touched. Peek stayed Shutdown. No D4iPad/Sim port
was started.

### What changed

Worktree `/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-fetch`,
branch `exclusive/0022-fetch-view` from `9676ead` (Kernarium-0022-clean).
Not pushed (origin is upstream `imxieyi/Kernarium`). Six files:
`guest_address_space.hpp` grows a default `host_pointer(address, size,
access)` that returns null; `StaticGuestMemory` returns the already
translated host pointer when the range sits in one RAM page, else null
(empty, page-crossing, MMIO, permission fault). `atomic_pointer` is the
same path. A64 miss-path fetch, CAS lookahead, `tracked_store_function`,
`fetch_instruction`, A32 `fetch_a32_bytes`, stale-validation, and
`persistent_identity_for` use `host_pointer` + memcpy and fall back to
`fetch` only when the view is unavailable. `make_packed` /
`ExecutableArena::store` / `install_shared_translation` copies were left
alone so the ABAB isolated the fetch view. The cheap
`locations_mutex_` prefix check was also deferred.

Named side binary `uml-darwin-0022-fetch-view-20261113` (inode 245695535,
md5 `a96eb7d3700a9ebafcf499b391f4aa9b`), built 4:04:50 PM ET against
kernel local2 (`6.18.60-g8246678b2d74`). Copies also sit next to official
in the dirty tree’s `bin/` and in `notes/macos-metal-desktop/`.

### Unit tests (4:05:25–4:05:28 PM ET)

macos-unit exclusive suites: `publication_gate`, `exclusive_completion`,
`a32-exclusive`, `exclusive-progress` PASS;
`reservation_alias` and `exclusive-events` FAIL the same way they do on
official 0022 (pre-existing). No worse.

### CPU benches (mem=2G ncpus=8, persist off)

Official 4:05:37–4:06:26 PM ET, fetch-view 4:06:34–4:07:25 PM ET. Swap
delta 0 both. Peak RSS official 1704 MiB, fetch-view 2059 MiB (sampler;
in the earlier official 0022 band).

| Bench | Official 0022 | Fetch-view |
| --- | ---: | ---: |
| compile_tiny_sha cold | 2.19 s | 2.10 s (−4 %) |
| compile_tiny_sha warm | 1.36 s | 1.33 s |
| compile_native_loop | 0.27 s | 0.27 s |
| native_loop | 0.57 s | 0.57 s |
| sha256_32m | 0.38 s | 0.38 s |
| apk_add_offline | 3.09 s | 3.13 s |

Compile holds within noise.

### Guest atomic-stress (8 × 200k, mem=2G)

Both PASS, `atomics=1`, swap delta 0. Official 4:07:32–4:07:53 PM ET,
peak RSS 1778 MiB. Fetch-view 4:07:59–4:08:20 PM ET, peak RSS 1805 MiB.

### Firefox + Chromium TTP, ABAB, memory-pressure preflight (4:09:03–4:25:04 PM ET)

Chromium labwc image for Chromium, default labwc image for Firefox,
native Metal 1920×1080, mem=4G ncpus=8, 8G JIT, persist off. Seconds
after process start (memory-sampler / launch time). Chrome = first
visible browser window after the empty desktop (New Tab / Loading /
example.com tab). Boot-console OCR ignored. English = “This domain is
for use”; full = Example Domain title + body. SWAP_ABORT never tripped;
swap used was flat or fell (1062.94M → 1006.94M over the ABAB). Peak
RSS stayed in the 4.5–4.9 GiB band (no 12G / 6.4G leak).

| Run | Window (ET) | READY | Chrome | English | Full | Learn more | Net | Peak RSS | Δ swap |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Firefox official r1 | 4:09:04–4:10:56 PM | 4 s | 20 s example.com/ | 21 s | 21 s | 24 s | 1 s | 4615 MiB | 0 |
| Firefox fetch r1 | 4:11:06–4:12:58 PM | 3 s | 16 s example.com/ | 18 s | 18 s | **missing** | 2 s | 4794 MiB | 0 |
| Firefox official r2 | 4:13:10–4:15:02 PM | 3 s | 16 s New Tab | 19 s | 19 s | 22 s | 3 s | 4468 MiB | 0 |
| Firefox fetch r2 | 4:15:14–4:17:06 PM | 3 s | 17 s example.com/ | 18 s | 18 s | 20 s | 1 s | 4890 MiB | 0 |
| Chromium official r1 | 4:17:16–4:19:09 PM | 4 s | 16 s Loading | 17 s | 17 s | 17 s | 1 s | 4917 MiB | 0 |
| Chromium fetch r1 | 4:19:15–4:21:08 PM | 3 s | 19 s Loading | 20 s | 20 s | 20 s | 1 s | 4504 MiB | 0 |
| Chromium official r2 | 4:21:19–4:23:12 PM | 3 s | 16 s Example Domain | 17 s | 17 s | 17 s | 1 s | 4708 MiB | 0 |
| Chromium fetch r2 | 4:23:12–4:25:04 PM | 2 s | 14 s Loading | 17 s | 17 s | 17 s | 3 s | 4754 MiB | 0 |

Firefox chrome mean 18 s → 16.5 s, English/full 20 s → 18 s. Chromium
chrome 16 s → 16.5 s, English/full 17 s → 18.5 s. Fetch Firefox r1 took
an RCU stall after the English body appeared and stayed on “Transferring
data from example.com…” through the end of the run (16:11:24–16:12:56 PM
ET); Learn more never arrived. Official runs had zero RCU stall reports.
Fetch r2 completed normally.

Shots and OCR: `~/linux-ios-bakeoff/notes/macos-metal-desktop/persist-ttp-ab-fv-{ff,cr}-{off,fv}-{1,2}-manual/`.
Scores: `fv-ttp-scores-20261113.txt`. Logs: `session-ab-fv-*-20261113-*.log`.

### Landing bar

Not met. Compile is within noise and tests are no worse, and memory is
sane, but TTP is not a clear win (Chromium is slightly worse; Firefox is
a noisy 1–2 s and includes a hung run). Official was not promoted.
linux-ios-fast is updated only to record the measurement, the pass-through
design, and the interactive-metrics harness. The fetch-view worktree still
holds the six-file diff; it is not on official 0022.

## Near pass-through execution (design) and interactive metrics (13 Nov 2026, 4:28 PM ET)

David’s goal is a usable desktop (snappy app launch, scrolling, typing),
not just benchmarks. After the fetch-view work: design in
`notes/near-pass-through-execution.md`. Copy guest ARM64 mostly verbatim,
patch only SVC / system-register / exclusive instructions, and map guest
user memory at identity host addresses so loads and stores need no
checks (UML process address space). The document lists the iOS blockers
(JIT W^X, address-space reservation, signals/page faults) and a rough
prototype plan. It is a stronger follow-on than `DESIGN.md` (fixed-offset
`guest_va + K` plus the existing translator); the 13 Nov
`UML_JIT_USER_MAP` prototype is not this mode and stays not landed.

The test harness now has interactive metrics, in addition to compile
benches and time-to-example.com:

- Guest page + CGI: `scripts/desktop-guest/interactive-metrics/`
- Labwc opt-in: `scripts/desktop-guest/start-desktop-labwc.sh` when
  `/usr/local/etc/interactive-metrics` is injected
- Host launcher: `scripts/macos-metal/measure-interactive.sh`
  Markers: `===INTERACTIVE_LAUNCH===` (first paint),
  `===INTERACTIVE_SCROLL===` (`fps=`, `p95_frame_ms=` over a 2 s
  programmatic scroll), `===INTERACTIVE_INPUT===` (real key/click to
  the next rAF; `vncdotool` can poke after
  `===INTERACTIVE_READY_FOR_INPUT===`)
- TTP scorer: `scripts/macos-metal/score-ttp-shots.py`

How to run them is in `REPRODUCE.md`. The pass-through prototype should
not land on compile/TTP alone if these interactive numbers do not move.


## Official 0022 usable-desktop interactive baseline (13 Nov 2026, 4:42–4:47 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host: Mac mini (M2 Pro,
16 GB), macOS Tahoe 26.7.3. Official 0022 exclusive-scope-removal
`uml-darwin-official-0022-20261113` (inode 245630846, md5
`6ea8180e05fc6736d32530811ba3c439`, 54,302,536 bytes) and live
`uml-darwin` (same md5) were not overwritten. Kernel local2
(`6.18.60-g8246678b2d74`). Persist off. Native Metal 1920×1080, `mem=4G`
`ncpus=8`, `--jit-cache-budget=8G`. Memory-pressure preflight and
SWAP_ABORT (start+2048M) on. No leftover `uml-darwin`. Peek and iPad
(A16) stayed Shutdown. Nothing was installed on a phone. Display
resolution, voxl, Screen Sharing, and Keychain were not changed.

Fetch-view was dropped after the not-land decision. Worktree
`Kernarium-0022-fetch` and branch `exclusive/0022-fetch-view` were
deleted (unique `.build/presets` was about 2.7G). The named side binary
`uml-darwin-0022-fetch-view-20261113` (md5
`a96eb7d3700a9ebafcf499b391f4aa9b`) is kept under the dirty tree’s
macos-integration bin and as a copy in `notes/macos-metal-desktop/`.

Harness fixes used for this baseline (this commit): Alpine’s labwc
busybox has no `httpd` applet, so a static aarch64 Linux Go server
`scripts/desktop-guest/interactive-metrics/metrics-httpd` (source
`metrics-httpd.go`, `CGO_ENABLED=0 GOOS=linux GOARCH=arm64`) is injected
via `--guest-file` and started by `interactive-metrics-start.sh`. Each
marker is prefixed with UTC `HH:MM:SS` and `up=` from `/proc/uptime`.
Input listeners are registered before `===INTERACTIVE_READY_FOR_INPUT===`
is posted; the guest evdev poke waits 0.5 s after READY. `vnc_rfb.py` is
an untracked host helper and is not in this tree (`vncdotool` is not
installed on the mini).

`first_paint_ms` is the in-page rAF after the metrics JS starts (a few
milliseconds once the page is running), not app-launch wall time. The
useful launch number is host wall clock from process start (log stamp)
and from `FIREFOX_START` / `CHROMIUM_START` until
`===INTERACTIVE_LAUNCH===`, also reported as the guest `up=` delta.

Two earlier Firefox probes (16:34:38 and 16:37:52 ET) failed before
`metrics-httpd` was in place and are not baseline. A 16:40:38 ET Firefox
run already had launch+scroll (fps=35.73, p95=149.66 ms) but no `up=`
stamps; Firefox r1 was rerun at 16:42:35 ET with the timestamped server.

| Run | Window (ET) | Browser start (guest up) | Launch from process start / from browser start (guest Δup) | first_paint_ms | Scroll fps | frames | duration_ms | p95_frame_ms | Input | Peak RSS | Swap start→end |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Firefox r1 | 4:42:35–4:43:39 PM | 4:42:39 PM, up=2.96 s | 19 s / 15 s (15.65 s) | 3.0 | 32.72 | 68 | 2077.9 | 149.50 | timeout, key_n=0 click_n=0 | 4528 MiB | 942.94→942.94M |
| Firefox r2 | 4:43:39–4:44:43 PM | 4:43:42 PM, up=2.83 s | 18 s / 15 s (15.79 s) | 30.0 | 42.80 | 86 | 2009.5 | 17.42 | timeout, key_n=0 click_n=0 | 5185 MiB | 942.94→934.94M |
| Chromium r1 | 4:44:43–4:45:47 PM | 4:44:47 PM, up=3.48 s | 12 s / 8 s (7.52 s) | 595.6 | 1.10 | 4 | 3646.9 | 3149.80 | timeout, key_n=0 click_n=0 | 4991 MiB | 934.94→934.94M |
| Chromium r2 | 4:45:47–4:46:51 PM | 4:45:51 PM, up=2.94 s | 12 s / 8 s (7.96 s) | 24.8 | 1.09 | 3 | 2762.1 | 2649.90 | timeout, key_n=0 click_n=0 | 4671 MiB | 934.94→934.94M |

Firefox scroll is in a usable band (~33–43 fps over a 2 s programmatic
scroll). p95 is noisy: r1 had a long frame (149.50 ms), r2 was smooth
(17.42 ms). Chromium reaches the metrics page faster than Firefox
(~8 s after browser start vs ~15 s) but its programmatic scroll is
effectively stalled (~1.1 fps, 3–4 frames, p95 2.6–3.1 s). That is the
official 0022 usable-desktop baseline, not a harness failure: the same
page and scroll script produced tens of Firefox frames in the same
session window.

Input is not yet a valid metric. After the listener-order fix, all four
runs still posted `===INTERACTIVE_INPUT=== why=timeout key_n=0 click_n=0`.
The guest evdev poke (`KEY_A` on `/dev/input/event0`, tablet
click on `/dev/input/event1`) and a host `VNC_POKE` to `127.0.0.1:5900`
both ran after READY (VNC_POKE at 4:43:06, 4:44:10, 4:45:13, and
4:46:18 PM ET). Trusted keydown/mousedown never reached the page.
Launch and scroll are the baseline; input latency is unresolved
(focus, evdev format, or native Metal not exposing TCP 5900 the way
the poke expects).

No SWAP_ABORT. Swap used was flat or slightly down. Logs stay on the
mini under `~/linux-ios-bakeoff/notes/macos-metal-desktop/`
(`session-interactive-official0022-{ff,cr}-{1,2}-20261113-16{42,43,44,45}*.log`
and matching `persist-memory-interactive-*`).

This baseline is the A side for the macOS-first near pass-through
prototype in `notes/near-pass-through-execution.md`. That work starts
from `9676ead` on a clean branch, env-gated and default off, and must
not land on official 0022 unless compile, TTP, and these interactive
numbers are a clear win with tests no worse.


## Chromium scroll and input-latency on official 0022 (13 Nov 2026, 4:55–5:05 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host and official 0022
`uml-darwin-official-0022-20261113` (md5 `6ea8180e05fc6736d32530811ba3c439`).
Kernel local2, persist off, native Metal 1920×1080, `mem=4G` `ncpus=8`,
`--jit-cache-budget=8G`, SWAP_ABORT on. The binary was not overwritten.
Peek and iPad (A16) stayed Shutdown.

The 4:42–4:47 PM ET usable-desktop baseline had Chromium programmatic
scroll at ~1.1 fps (p95 2.6–3.1 s) versus Firefox 33–43 fps, and every
input poke timed out. David prefers Chromium, so this pass diagnosed
and fixed those two metrics on official 0022 before continuing the
near pass-through prototype.

### Diagnosis

The metrics page was `visibilityState=visible` and not `document.hidden`
during the 1 fps scrolls (`hasFocus` was 0 at first paint and 1 by the
end of the scroll). This is not Chrome’s hidden-tab 1 fps rAF cap.
Unthrottle flags alone (`--disable-background-timer-throttling`,
`--disable-renderer-backgrounding`,
`--disable-backgrounding-occluded-windows`) stayed at 1.13 fps.

The GPU process was alive (`--type=gpu-process --gpu-recent-crash-count=0`,
`--render-node-override=/dev/dri/renderD128`). There was no SwiftShader
fallback line and no crashpad GPU abort. `vaInitialize failed: unknown
libva error` is a harmless missing VA-API. Alpine Chromium is 156.0.8078.79
with a wrapper that already passes `--ozone-platform-hint=auto`.

Allowed GL implementations are only `egl-angle` + `opengl` / `opengles` /
`vulkan`. `--use-gl=egl` is rejected (`egl-gles2,angle=none` not allowed)
and the GPU process restarts with `--use-gl=disabled`. Explicit
`--use-angle=vulkan` logs `'--ozone-platform=wayland' is not compatible
with Vulkan` and `Failed to create vulkan surface`.
`--disable-features=Vulkan,VulkanFromANGLE,DefaultANGLEVulkan` (keeping
default GPU compositing) still scrolled at 0.78 fps, so the stall is
the default Wayland GPU compositor path itself, not a silent Vulkan
choice.

`--disable-gpu` jumped to 9.17 fps (p95 354 ms).
`--disable-gpu-compositing` plus `--enable-gpu-rasterization` is the
winning combination: software compositing, GPU raster kept, no GL
retry tax on first paint.

| Flags (one diagnostic run, 8 s input timeout) | Scroll fps | frames | p95_frame_ms | first_paint_ms |
| --- | ---: | ---: | ---: | ---: |
| Baseline (`--no-sandbox --password-store=basic` only) | 0.56 | 2 | 3283.20 | 582.7 |
| Unthrottle only | 1.13 | 3 | 2283.30 | 681.8 |
| `--disable-features=Vulkan,...` (GPU compositing on) | 0.78 | 2 | 2566.50 | 619.7 |
| `--disable-gpu` | 9.17 | 19 | 354.00 | 541.4 |
| `--use-gl=egl` (rejected → `--use-gl=disabled`) | 12.54 | 26 | 96.50 | 1452.4 |
| `--use-gl=angle --use-angle=opengles` (same fallback) | 12.96 | 26 | 182.90 | 1542.5 |
| `--use-gl=angle --use-angle=opengl` (same fallback) | 12.14 | 25 | 220.06 | 1673.9 |
| `--use-angle=vulkan` (Wayland-incompatible) | 6.46 | 14 | 583.30 | 491.8 |
| **`--disable-gpu-compositing --enable-gpu-rasterization`** | **10.41** | 21 | **211.00** | **480.2** |

The 12 fps rows paid a 1.0–1.5 s first-paint tax while GL init failed.
The baked flags take the reliable compositor-off path.

### Input path

Guest writes to the Darwin UML VNC evdev nodes do work on
`--gpu-display=native`. Host `VNC_POKE` to `127.0.0.1:5900` does not
(the listener speaks RFB 003.889 with no None auth). The earlier
timeouts were a bad poke: KEY_A before focus, `BTN_LEFT` without
`BTN_TOUCH`, and ABS coordinates 960×540 as if the tablet were
0..1919×0..1079. The tablet is `INPUT_PROP_DIRECT` with a 16-bit ABS
range (`PROP=2`, `ABS=3`). A mid-range `BTN_TOUCH`+`BTN_LEFT` at
(32767, 32767), then KEY_A, produces trusted events.

`scripts/desktop-guest/interactive-metrics/evdev-poke.sh` is that
helper. The metrics page now records `vis=` / `hasFocus=` and finishes
the input metric once it has one key and one click.

### Official confirmation (winning flags baked)

`scripts/desktop-guest/chromium-flags` (also copied to the mini FAST
overlay) is now:

```
--no-sandbox --password-store=basic
--disable-background-timer-throttling
--disable-renderer-backgrounding
--disable-backgrounding-occluded-windows
--disable-features=CalculateNativeWinOcclusion,IntensiveWakeUpThrottling
--disable-gpu-compositing --enable-gpu-rasterization
--num-raster-threads=4 --start-maximized
```

`start-desktop-labwc.sh` still adds `--ozone-platform=wayland`. Verbose
Chromium logging is opt-in (`CHROMIUM_ENABLE_LOGGING=1`).

| Run | Window (ET) | Launch from process / from CHROMIUM_START (guest Δup) | first_paint_ms | Scroll fps | frames | p95_frame_ms | Input | Peak RSS | Swap |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| Baseline r1 | 4:44:43–4:45:47 PM | 12 s / 8 s (7.52 s) | 595.6 | 1.10 | 4 | 3149.80 | timeout, 0/0 | 4991 MiB | 934.94→934.94M |
| Baseline r2 | 4:45:47–4:46:51 PM | 12 s / 8 s (7.96 s) | 24.8 | 1.09 | 3 | 2649.90 | timeout, 0/0 | 4671 MiB | 934.94→934.94M |
| Fix r1 | 5:02:10–5:03:14 PM | 11 s / 7 s (7.48 s) | 496.0 | 7.93 | 16 | 633.40 | timeout, key 23.75 ms (n=4), click missed (ABS 960,540) | 4193 MiB | 926.94→926.94M |
| Fix r2 | 5:03:14–5:04:18 PM | 10 s / 7 s (7.21 s) | 435.5 | 7.27 | 15 | 583.30 | timeout, key 8.53 ms (n=4), click missed | 4397 MiB | 926.94→926.94M |
| Input confirm (16-bit ABS mid) | 5:04:38–5:05:12 PM | ~11 s / ~7 s (7.52 s) | 388.4 | 9.41 | 19 | 366.70 | **ok, key 12.30 ms, click 20.30 ms** | 4420 MiB | 926.94→926.94M |

Chromium scroll is about 7–10 fps (p95 0.37–0.63 s) versus the ~1.1 fps
(p95 2.6–3.1 s) baseline, still short of Firefox’s 33–43 fps. Launch
stays in the same ~7 s-after-browser-start band. Input latency is now
a valid metric once the poke uses the 16-bit tablet mid (fix r1/r2
used the old 1920×1080 mid and only got keys). No SWAP_ABORT. Swap
used was flat. Official 0022 is unchanged.

Logs stay on the mini under `~/linux-ios-bakeoff/notes/macos-metal-desktop/`
(`session-interactive-official0022-cr-diag-*` and
`session-interactive-official0022-cr-fix-*`).

The near pass-through worktree
`/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-passthrough`
(branch `exclusive/0022-near-pass-through` from `9676ead`) is in place
with shared `.build/{dependencies,kernel,rootfs}` symlinks. Prototype
code has not been written yet.

## Official 0022 warm second-page timing (13 Nov 2026, 5:13–5:16 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host and official 0022
`uml-darwin-official-0022-20261113` (md5 `6ea8180e05fc6736d32530811ba3c439`).
Kernel local2, persist off, native Metal 1920×1080, `mem=4G` `ncpus=8`,
`--jit-cache-budget=8G`, SWAP_ABORT on. Baked Chromium flags from the
5:05 PM ET compositor fix. The official binary was not overwritten.
Peek and iPad (A16) stayed Shutdown. Swap used was flat at 918.94M;
no SWAP_ABORT.

David asked about the ~8 s Chromium first-page time. That number is
cold: process start / `CHROMIUM_START` until the first in-page rAF on
a fresh browser. The number he will feel after that is a same-window
navigation to a second local page.

The harness now does that after `===INTERACTIVE_INPUT===` (whether
`why=ok` or `why=timeout`): the landing page posts
`===INTERACTIVE_WARM_NAV=== from=... to=/warm.html` and
`location.assign("/warm.html")`. `warm.html` is a distinct modest
page (header + three cards). On its first rAF it posts
`===INTERACTIVE_WARM_LAUNCH===` with in-page `first_paint_ms` plus
Navigation Timing (`nav_ms`, `response_ms`, `dcl_ms`, `load_ms`),
then `===INTERACTIVE_DONE=== why=warm`. The felt time is the guest
`up=` delta from `WARM_NAV` to `WARM_LAUNCH`. `first_paint_ms` is
still only time to the first rAF once that page's JS is running.

`metrics-httpd` serves `/warm.html`. `measure-interactive.sh` injects
it with `--guest-file`. Two Chromium runs at 5:07–5:10 PM ET reached
`WARM_NAV` but hung until the 110 s DONE wait because that inject was
missing (404). Those logs are not the warm baseline (scroll/input from
them still match the compositor-fix band: 9.47 / 6.97 fps, input ok).
The table below is the rerun after the inject, 5:13–5:16 PM ET.

| Run | Window (ET) | Cold launch process / browser start (guest Δup) | first_paint_ms | Scroll fps | frames | p95_frame_ms | Input | Warm `up=` WARM_NAV→WARM_LAUNCH | nav_ms / response_ms | Peak RSS | Swap |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- |
| Chromium r1 | 5:13:02–5:13:35 PM | 12 s / 8 s (7.62 s) | 502.7 | 9.47 | 19 | 500.00 | ok, key 7.70 ms, click 14.60 ms | **0.60 s** | 421.5 / 149.0 | 4256 MiB | 918.94→918.94M |
| Chromium r2 | 5:13:36–5:14:08 PM | 10 s / 7 s (7.50 s) | 673.3 | 9.25 | 19 | 283.40 | ok, key 12.90 ms, click 16.90 ms | **0.64 s** | 459.4 / 144.4 | 5047 MiB | 918.94→918.94M |
| Firefox r1 | 5:14:09–5:15:12 PM | 19 s / 16 s (15.74 s) | 20.0 | 39.36 | 80 | 66.64 | timeout, 0/0 (`hasFocus=0`) | **1.85 s** | 0.0 / 773.0 | 4812 MiB | 918.94→918.94M |
| Firefox r2 | 5:15:12–5:16:16 PM | 19 s / 15 s (15.91 s) | 3.0 | 39.72 | 80 | 66.66 | timeout, 0/0 (`hasFocus=0`) | **1.32 s** | 0.0 / 362.0 | 5063 MiB | 918.94→918.94M |

Once Chromium is up, the second page in the same window is about
0.60–0.64 s (Navigation Timing `nav_ms` 421–459 ms agrees). That is
the number David will feel, not the ~7–8 s cold `CHROMIUM_START` to
first page. Firefox's cold first page is still ~15–16 s after
`FIREFOX_START`; its same-window second page is 1.32–1.85 s. Firefox
Navigation Timing fields were mostly 0 at first rAF (`nav_ms` /
`dcl_ms` / `load_ms`); use the `up=` delta. The evdev poke still
does not focus Firefox (`hasFocus=0`, input timeout); warm navigation
still runs after the input timeout and is a valid same-window timing.

Logs on the mini:
`session-interactive-official0022-cr-warm-{1,2}-20261113-1713{02,36}.log`
and
`session-interactive-official0022-ff-warm-{1,2}-20261113-171{409,512}.log`.

## Chromium scroll flag sweep on official 0022 (13 Nov 2026, 5:23–5:30 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host and official 0022
`uml-darwin-official-0022-20261113` (md5 `6ea8180e05fc6736d32530811ba3c439`).
Kernel local2, persist off, native Metal 1920×1080, `mem=4G` `ncpus=8`,
`--jit-cache-budget=8G`, SWAP_ABORT on. Each variant is the baked
compositor-fix flags plus one change. `UML_CHROMIUM_FLAGS_FILE` was
applied (confirmed on the `===CHROMIUM_FLAGS===` line). Official 0022
was not overwritten. Peek and iPad (A16) stayed Shutdown. Swap used
was 918.94M then 910.94M, flat within each run; no SWAP_ABORT.

The goal was to push Chromium programmatic-scroll rAF fps from the
baked 9.25–9.47 band toward Firefox’s 33–43 fps. Only a measured clear
win would be baked. None was.

A first 5:17–5:23 PM ET loop did not actually apply the variant files
(zsh did not word-split the tag/flag pair, so the harness fell back to
the baked flags). Those `official0022-cr-rscroll-*` logs are accidental
baked repeats (about 8–12 fps) and are not this table.

The scroll metric is rAF callbacks during a 2 s `scrollBy(0, 48)` loop,
the same as Firefox’s 33–43 fps number. It is a present-rate proxy only
while rAF is vsync- or present-capped.

| Variant (one run unless noted) | Window (ET) | Scroll fps | frames | p95_frame_ms | first_paint_ms | vs baked 9.25–9.47 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Baked (warm r1 / r2, 5:13–5:14 PM) | 5:13:02 / 5:13:36 PM | 9.47 / 9.25 | 19 / 19 | 500.00 / 283.40 | 502.7 / 673.3 | baseline |
| `--num-raster-threads=1` | 5:23:19 PM | 6.72 | 14 | 350.00 | 573.6 | worse |
| `--num-raster-threads=2` | 5:23:52 PM | 6.45 | 13 | 409.30 | 482.2 | worse |
| `--num-raster-threads=8` | 5:24:25 PM | 8.23 | 17 | 333.20 | 490.8 | no win |
| `--disable-smooth-scrolling` + `SmoothScrolling` off | 5:24:59 PM | 8.95 | 19 | 385.60 | 45.8 | no win |
| `--disable-gpu-vsync --disable-frame-rate-limit` | 5:25:34 PM | 142.52 | 286 | 19.20 | 31.8 | rAF uncapped, not baked |
| same, confirm | 5:28:53 PM | 138.65 | 279 | 25.20 | 16.0 | rAF uncapped, not baked |
| `--disable-gpu-vsync` only | 5:29:27 PM | 8.30 | 17 | 333.25 | 439.8 | no win |
| `--disable-frame-rate-limit` only | 5:30:01 PM | 154.82 | 310 | 18.00 | 100.0 | rAF uncapped, not baked |
| `--enable-oop-rasterization` + `CanvasOopRasterization` | 5:26:11 PM | 10.70 | 22 | 169.30 | 496.2 | noise, not baked |
| `--disable-zero-copy` + ZeroCopy features off | 5:26:41 PM | 7.84 | 16 | 533.30 | 502.8 | no win |
| `--enable-zero-copy` | 5:27:15 PM | 7.37 | 15 | 450.00 | 449.1 | no win |
| `--disable-partial-raster --cc-scroll-animation-duration-in-seconds=0` | 5:27:49 PM | 9.83 | 20 | 316.70 | 452.4 | no win |

`--disable-frame-rate-limit` (alone or with `--disable-gpu-vsync`)
makes `requestAnimationFrame` fire as fast as the renderer main thread
can run, so the harness counts ~140–155 JS callbacks per second with a
~18–25 ms p95. That is not a presented-frame rate and is not comparable
to Firefox’s vsync-capped 33–43 fps. `--disable-gpu-vsync` alone stays
in the baked band. The flags are not baked.

Raster thread counts 1 and 2 are worse than 4. 8 is no win. Zero-copy
on or off, smooth-scrolling off, and the partial-raster / scroll-animation
pair do not help. OOP raster was 10.70 fps / p95 169 ms on one run,
inside the earlier 7–10 fps (and accidental baked-repeat 8–12 fps)
noise, and still far from Firefox. Baked `chromium-flags` is unchanged.

Experiment files (not used by the default start script) live next to
the baked flags as `scripts/desktop-guest/chromium-flags-{raster1,raster2,raster8,nosmooth,novsync,novsync-vsynconly,novsync-frlonly,oop,nozerocopy,zerocopy,norasterlimit}`.
Logs on the mini: `session-interactive-official0022-cr-scrollx-*`.

## Near pass-through prototype (branch only, 13 Nov 2026, 5:36–5:38 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Worktree
`/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-passthrough`,
branch `exclusive/0022-near-pass-through` from official 0022 `9676ead`,
commit `8cfda0a` (not pushed; Kernarium is not pushed from the mini).
Official 0022 `uml-darwin-official-0022-20261113` md5 is still
`6ea8180e05fc6736d32530811ba3c439`. The worktree has a unique
`.build/presets` and did not write that binary. Peek and iPad (A16)
stayed Shutdown. No `uml-darwin` run.

The prototype is env-gated (`UML_JIT_NEAR_PASSTHROUGH=1`) and default
off. On iOS the flag is ignored. `compile_once` tries a verbatim
emit and falls back to today's translator if the block is refused;
with the flag unset the hook is a no-op.

What is in `8cfda0a`:

- A conservative A64 classifier: GPR data-processing that does not use
  SP or X18, NOP, DMB/DSB, intra-block `B` / `B.cond`, and a terminal
  inter-block `B`. Refuse SVC/sysreg/exclusives, ADR/ADRP, literals,
  BL, BR/RET, ISB, SIMD/FP/SME, SP, X18, mid-block leaving branches.
- A load-all / spill-all ABI (custom 80-byte frame, guest X0–X30 in
  host Xn except X18 and SP, NZCV load/spill, `Event::continued`,
  `link_target_safe=false`). No mid-struct `JitChainState` field.
- An identity probe at K = 0 (`VM_FLAGS_FIXED`, no bitmap).
  `identity_ready()` stays false until an eager map hook and a fault
  path exist, so raw loads/stores stay refused.

Standalone unit tests (classifier, emit, identity) passed at 5:38:10
PM ET (`/tmp/arm64-near-pass-through-tests`, guest page 4K). The
`VM_FLAGS_FIXED` K = 0 try (then released) was:

| Range | Size | Result |
| --- | --- | --- |
| `0x40000` | 16 MiB | fail kr=1 |
| `0x40000000` | 1 GiB | fail kr=1 |
| `0x100000000` | 1 GiB | fail kr=1 |
| `0x550000000000` | 4 GiB | ok |
| `0x7e0000000000` | 4 GiB | ok |
| `0x7f0000000000` | 4 GiB | ok |
| `0x7fc000000000` | 4 GiB | ok |
| `0x7ffe00000000` | 1 GiB | ok |

Low / first-4-GiB static images cannot be reserved on this host.
Several musl-PIE-class high windows *can* be reserved at K = 0 (17 GiB
if all five succeed). That is more encouraging than the 13 Nov
user-map inventory, which did not get identity near `0x7fff…` and then
used a wrap `K` plus a bitmap (and regressed dash/gcc). It is still
not a working identity map: no `vm_remap` on guest map/unmap/protect
and no fault installer. `compile_once` only inventories, and does not
hold those 17 GiB, if the flag is on during a boot.

No side `uml-darwin` was built, so there is no atomic-stress, static
busybox/hello, desktop boot, CPU bench, TTP ABAB, or interactive
comparison vs official 0022. Flag-on would only verbatim ALU-only
blocks; most C frames use SP and would fall back. That is not a
clear-win land candidate. The prototype stays on the branch; official
0022 is unchanged. Full write-up:
`notes/near-pass-through-prototype.md` in the Kernarium worktree.

## Firefox input focus fix on official 0022 (13 Nov 2026, 5:40–5:41 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Same host and official 0022
`uml-darwin-official-0022-20261113` (md5 `6ea8180e05fc6736d32530811ba3c439`).
Kernel local2, persist off, native Metal 1920×1080, `mem=4G` `ncpus=8`,
`--jit-cache-budget=8G`, SWAP_ABORT on. Official 0022 was not overwritten.
Peek and iPad (A16) stayed Shutdown. Swap used was 910.94M then 902.94M;
no SWAP_ABORT.

The 5:14–5:16 PM ET warm runs had Firefox input `why=timeout`,
`hasFocus=0`, even though evdev writes succeeded. Launch and scroll
still reported `hasFocus=1`. The mid-tablet poke (ABS 32767,32767) was
hitting the labwc desktop: Firefox is not started with
`--start-maximized`, so a default window often does not cover the
center of 1920×1080, and the click stole focus.

The harness now (1) writes a labwc `rc.xml` window rule that Maximizes
Firefox and Chromium on map when interactive metrics are on, (2) seeds
the kernarium profile `xulstore.json` with `sizemode=maximized` at
1920×1080, and (3) pokes a focus click at upper-center (ABS_Y≈19660)
then mid before KEY_A. `measure-interactive.sh` prefers the repo
Firefox profile script.

| Run | Window (ET) | Cold launch process / FIREFOX_START (guest Δup) | first_paint_ms | Scroll fps | frames | p95_frame_ms | Input | Warm `up=` | Peak RSS | Swap |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |
| Firefox r1 (warm, before fix) | 5:14:09–5:15:12 PM | 19 s / 16 s (15.74 s) | 20.0 | 39.36 | 80 | 66.64 | timeout, 0/0 (`hasFocus=0`) | 1.85 s | 4812 MiB | 918.94→918.94M |
| Firefox r2 (warm, before fix) | 5:15:12–5:16:16 PM | 19 s / 15 s (15.91 s) | 3.0 | 39.72 | 80 | 66.66 | timeout, 0/0 (`hasFocus=0`) | 1.32 s | 5063 MiB | 918.94→918.94M |
| Firefox r1 | 5:40:28–5:41:01 PM | 20 s / 16 s (15.93 s) | 27.0 | 40.68 | 82 | 50.70 | **ok, key 2.00 ms, click 97.00 ms** (n=1/2, `hasFocus=1`) | **1.19 s** | 4477 MiB | 910.94→902.94M |
| Firefox r2 | 5:41:01–5:41:34 PM | 19 s / 15 s (15.78 s) | 42.0 | 42.15 | 85 | 66.30 | **ok, key 5.00 ms, click 69.00 ms** (n=1/2, `hasFocus=1`) | **1.16 s** | 4615 MiB | 902.94→902.94M |

`click_n=2` is the focus mid-click plus the following mid click, both
after the page armed. Click latency (69–97 ms) is slower than
Chromium's ~15–17 ms and includes the first hit after the upper-center
focus poke. Keys are 2–5 ms. Warm same-window navigation is 1.16–1.19 s
(shorter than the pre-fix 1.32–1.85 s, which included a 20 s input
timeout before navigate). Scroll stays in the 39–42 fps band.

Logs:
`session-interactive-official0022-ff-input-{1,2}-20261113-174{028,101}.log`.

## Near pass-through identity hook (branch only, 13 Nov 2026, 5:46–5:54 PM ET)

Date: Fri Nov 13, 2026, America/New_York. Worktree
`/Users/davidhope/linux-ios-bakeoff/src/Kernarium-0022-passthrough`,
branch `exclusive/0022-near-pass-through` (from official 0022 `9676ead`,
prior commit `8cfda0a`). Official 0022
`uml-darwin-official-0022-20261113` md5 stayed
`6ea8180e05fc6736d32530811ba3c439` and was never overwritten. Kernel
for the measured side binary is **local2** `6.18.60-g8246678b2d74`.
persist off. Peek and iPad (A16) stayed Shutdown. Swap used stayed
894.94M; no SWAP_ABORT. Kernarium is not pushed from the mini or to
upstream.

This pass pushed the ALU-only prototype toward something measurable:
verbatim SP-relative and plain loads/stores, a high-window K = 0
identity reservation with a `vm_remap` map hook and a SIGSEGV/SIGBUS
retry path, a **side** `uml-darwin` only, then hello / atomic-stress.
Land bar was a measured clear win vs official 0022 (compile within
noise, TTP better, interactive no worse, memory sane, tests no worse).
That bar was not met.

Standalone unit tests (including new SP-relative classify cases)
passed at **5:48:22 PM ET**. Default-off does not reserve and is a
no-op in `compile_once`.

Side binary (unique passthrough `.build/presets/macos-integration`,
Ninja Release): first configure accidentally accepted **local1**;
relinked to local2 at 5:50:50 PM ET before measurement. After adding a
3.75 GiB Linux-stack window the named image md5 is
`20ffc0653cf26e540c96afb4c2fd96a2`
(`uml-darwin-0022-near-pt-20261113` under the worktree bin and
`notes/macos-metal-desktop/`). Runtime reserved 4 GiB at
`0x7f0000000000`, 4 GiB at `0x7fc000000000`, and 3.75 GiB at
`0x7fff00000000` (a 4 GiB FIXED at that base fails: the last 256 MiB
of the 47-bit space is rejected). Not the 17 GiB test inventory.

| Run | Window (ET) | Flag | Result |
| --- | --- | --- | --- |
| hello (2×4 GiB windows only) | 5:51:19–5:51:20 PM | on | panic, status=6. Hook armed. FAR `0x7fffd369de90` (guest `/init` SP) was outside those windows. Host stack is at `0x16…`, not an alias. |
| hello default-off control | 5:52:27–5:52:29 PM | off | **PASS** `===HELLO===` / `===HELLO_DONE===`, status=0, no reservation. |
| hello + stack window | 5:53:17–5:53:18 PM | on | 3 windows reserved; still panics at initramfs `/init` before EXT4. FAR=`0x100` (write, esr=`0x92000046`), SP now in the stack window, X18=0, X1=0, X30=`0x4135d8`. status=6. |
| atomic-stress + stack window | 5:53:54–5:53:55 PM | on | Same panic (FAR=`0x100`, X18=0), status=6. No `===ATOMIC_STRESS===`. |

Official 0022 atomic-stress earlier today (4:07:32–4:07:53 PM ET) was
`===ATOMIC_STRESS_DONE=== PASS` on the same kernel and rootfs.

TTP and interactive vs official 0022 were not run: a desktop boot
would hit the same initramfs `/init` panic.

Why this stays on the branch:

- Low 4 GiB cannot be reserved FIXED (kr=1). initramfs `/init` is a
  low static image (`0x4135d8`). Verbatim loads/stores to its
  data/.got cannot be identity-mapped. Structural blocker.
- After covering the Linux user stack, the crash is a write to `0x100`
  with X18 already 0 mid-body (Darwin may clobber the platform
  register used as the SP-switch slot pointer).
- 4K guest / 16K host still remaps only uniform 16 KiB spans.

Default-off on this same side binary boots hello, so the regression is
the armed hook. Official 0022 is unchanged. Full write-up:
`notes/near-pass-through-prototype.md` in the Kernarium worktree.
Logs under
`/Users/davidhope/linux-ios-bakeoff/notes/jit-baseline/compile-alloc/hello-near-pt-*.log`
and `atomic-stress-near-pt-on-stackwin-20261113-175354.log`.

## Near pass-through /init fix and defer variant (branch only, 13 Nov 2026, 6:07–6:48 PM ET)

Kernarium `exclusive/0022-near-pass-through` @ `ee5dc0f` (code) and
`895e750` (notes), local only, not pushed. Side binary md5
`f0b8cdf916f721c621523383315212a2`. Official 0022 (`6ea8180e…`) not
touched.

Root cause of the `/init` write to `0x100`: it was not X18. A patched
terminal `B` branched over the spill-all, so x15 still held guest X15
(0) when the exit stored `CpuState::pc` (offset 0x100). With that
fixed, the next fault (`0xcd0`) came from the 80-byte frame not saving
host x22–x28, which load-all clobbers; moved to the official 128-byte
extended frame. The mid-block software-MMU fallback then returned
`Event::fatal` (no handler for some forms), so memory and SP-relative
blocks now go to the normal translator per block, and only ALU-only
blocks run verbatim.

Flag on: hello PASS 6:14:44 PM ET, atomic-stress PASS 6:14:55–6:15:18
PM ET; default-off hello PASS 6:15:26 PM ET.

Vs official 0022 (ABAB, labwc Metal 1920×1080, 4G/8 CPU, 8G JIT,
persist off), example.com full TTP in seconds: Firefox 32/23 vs 18/18,
Chromium 16/14 vs 13/11; DESKTOP_READY ~+1 s. Interactive: Firefox
scroll 24.5/36.8 fps vs 39.9 (same session), Chromium 12.2/7.3 vs 8.7,
input latency about the same. Clearly worse on TTP, so not landed.
Likely cause: verbatim blocks give up block linking and do a full
register load/spill on every entry. Details are in
`notes/near-pass-through-prototype.md`.

## iOS targets: interactive harness + Chromium flags on official 0022 (13 Nov 2026, 6:52–7:40 PM ET)

Near pass-through is parked (not landed). This ports the 13 Nov uml-darwin
winners to Designed-for-iPad (D4iPad, Aqua LaunchAgent + lldb `jit_serve`)
on official 0022: the Chromium flags from `ea2b7a9`
(`--disable-gpu-compositing --enable-gpu-rasterization` …) and the
interactive harness (cold launch, scroll fps, input latency, warm second
page, Firefox maximize via xulstore + labwc rule). Persist off; Peek and
iPad (A16) Shutdown during D4iPad runs; one run at a time; preflight and
SWAP_ABORT on. Official `uml-darwin-official-0022-20261113` md5
`6ea8180e05fc6736d32530811ba3c439` was only used read-only for bakes.

**Images.** D4iPad/Sim have no `--guest-file`, so the harness is baked.
`scripts/macos-metal/bake-ios-interactive-image.sh` APFS-clones a base
image and boots official 0022 once with `UML_BOOT_UPPER=none`;
`bake-ios-interactive-guest.sh` installs the repo `start-desktop-labwc.sh`
as `start-desktop.sh`, plus `/usr/local/etc/{interactive-metrics,desktop-browser,chromium-flags}`
and `/usr/local/share/interactive-metrics/*`, then remounts ro and powers
off (~5 s each, journal clean, incompat 0x2c2). Work images (originals
untouched):
`alpine-3.24.2-desktop-labwc-interactive-ff-20261113.ext4` (from
`labwc.ext4`) and `alpine-3.24.2-desktop-labwc-interactive-cr-20261113.ext4`
(from `labwc-chromium-d4ipad-20261113.ext4`), baked both in
`/Volumes/KernariumCS/rootfs/starter-20261112/` (Sim uses symlinks) and
in-place as clones in the D4iPad container Documents (no extra disk).
Rebaked 7:11–7:12 PM ET after the touch fix below.

**Touch fix.** iOS exposes a virtio `Kernarium Touchscreen` (MT slots,
ABS 0..32767), not the VNC tablet (0..65535). `evdev-poke.sh` fell back
to the keyboard node, so `click_n=0` (int-ff-1, 7:07–7:10 PM ET). It now
matches the touchscreen, halves coordinates and writes BTN_TOUCH + MT
slot/tracking/position like `touchscreen.cpp`; the kernel drops MT codes
the VNC tablet does not advertise, so uml-darwin is unchanged.

**Launchers.** `launch-d4ipad-0022.sh` / `bootstrap-d4ipad-0022.sh` /
plist take optional JIT budget and L1 cap args; `launch-sim-0022-test.sh`
takes `JIT_BUDGET` / `JIT_EXECUTOR_BUDGET` env. SWAP_ABORT previously only
logged; it now TERMs then KILLs `Kernarium.app/Kernarium`, and the sampler
covers the 900 s session. `run-d4ipad-interactive.sh` runs one session and
copies `guest-serial.log`; `parse-ios-interactive.py` prints the row.
A 7:04 PM ET attempt was refused by preflight (headroom 5941M < 6144M,
file cache from the image compares); `purge` cleared it.

### D4iPad results (cold = INTERACTIVE_LAUNCH guest up − browser START up)

| Run | Window (ET) | JIT budget / L1 | Cold launch | first_paint_ms | Scroll fps (frames, p95 ms) | Input key / click ms | Warm Δup / nav_ms | Shared insert / evict | Peak RSS |
| --- | --- | --- | ---: | ---: | --- | --- | --- | --- | ---: |
| FF int-ff-1 (pre touch fix) | 7:07–7:10 PM | 2G/128M | 38.5 s | 12.0 | 43.42 (87, 50.0) | timeout, key 130.5 / click n=0 | 3.49 s / 1940 | — | — |
| FF int2-ff-1 | 7:12–7:15 PM | 2G/128M | 38.75 s | 22.0 | 48.91 (98, 49.8) | ok, 500.0 / 218.0 | 3.26 s / 2007 | 2.85M / 2.50M | 6531 MiB |
| FF int2-ff-2 | 7:15–7:18 PM | 2G/128M | 40.19 s | 16.0 | 34.67 (72, 116.8) | ok, 618.3 / 188.0 | 2.88 s / 0 | 2.91M / 2.56M | 6638 MiB |
| CR int2-cr-1 | 7:18–7:28 PM | 2G/128M | 22.06 s | 1775.9 | **stalled** at SCROLL_START (guest 0.2% CPU, killed 7:28) | — | — | 1.39M / 0.95M (30 s) | 5207 MiB |
| CR int2-cr-2 | 7:29–7:32 PM | 2G/128M | 21.62 s | 1595.3 | 3.31 (7, 1399.9) | ok, 75.6 / 233.4 | 3.56 s / 2685 | 2.47M / 2.04M | 6401 MiB |
| CR jit4G-cr-1 | 7:34–7:37 PM | **4G/128M** | **8.65 s** | 506.4 | 9.36 (19, 438.2) | ok, 22.4 / 59.9 | **0.74 s** / 535 | 1.39M / **18k** | 5525 MiB |
| CR jit4G-cr-2 | 7:37–7:40 PM | **4G/128M** | **8.53 s** | 656.4 | 12.92 (26, 158.9) | ok, 31.5 / 49.9 | **0.60 s** / 432 | 1.40M / **29k** | 5531 MiB |
| FF jit4G-ff-1 | 7:41–7:44 PM | **4G/128M** | **18.66 s** | 7.0 | 52.21 (107, 33.5) | ok, 130.0 / 135.7 | **1.98 s** / 1169 | 1.40M / 226k | 5662 MiB |
| FF jit4G-ff-2 | 7:44–7:47 PM | **4G/128M** | **18.54 s** | 7.0 | 48.25 (99, 17.4) | ok, 131.0 / 74.7 | **1.76 s** / 0 | 1.41M / 234k | 5669 MiB |

uml-darwin official 0022 reference (5:13–5:41 PM ET tables above):
Chromium cold 7.5–7.6 s from CHROMIUM_START, scroll 9.25–9.47 fps,
key 7.7–12.9 / click 14.6–16.9 ms, warm 0.60–0.64 s; Firefox cold
15.8–15.9 s, scroll 40.7–42.2 fps, warm 1.16–1.19 s.

**Profile: the D4iPad gap was shared-translation-cache thrash.** At
2G/128M with 8 vCPUs the private L1s take 1 GiB and the shared tier gets
the other 1 GiB. `JIT_SHARED_STATS` showed it pinned at
`accounted≈max=1073847616` with 88% of insertions evicted (FF 2.50M of
2.85M; CR 2.04M of 2.47M). uml-darwin runs with an 8G whole budget. The
debugger-prepared executable region depends only on the L1 cap (still
39912 pages / 623.6 MiB), so raising the whole budget to 4G (3 GiB shared)
costs no extra debugger mapping. Result: Chromium evictions fell ~100×,
cold launch 21.6→8.6 s (uml-darwin 7.5 s), warm second page 3.6→0.6–0.7 s
(= uml-darwin), clicks 233→50–60 ms, scroll 3.3→9.4–12.9 fps, and peak
RSS went *down* (6.4→5.5 GiB) because less is retranslated. Firefox at
4G: cold 38.8–40.2→18.5–18.7 s (uml-darwin 15.8–15.9 s), warm 2.9–3.3→1.8–2.0 s,
scroll 48–52 fps, evictions 2.5M→0.23M, RSS 6.6→5.7 GiB. Swap stayed
862.94M throughout. **Landed: D4iPad default is now 4G/128M.**

### Simulator results (Peek iPhone 17, parallel=NO, one destination; 8:01–8:20 PM ET)

Peek was booted at 7:48 PM ET, but `simctl bootstatus` hung and the
first attempt (7:55–8:00 PM ET) failed with “Simulator device failed to
launch … system shell probably crashed” (SpringBoard not up); discarded.
After a clean shutdown and reboot at 8:01 PM ET the runs below went one
at a time via `run-sim-interactive.sh` (`UML_ALLOW_HEAVY=1` only for the
start preflight; SWAP_ABORT on and now kills the app). Swap 854.94→846.94M,
no SWAP_ABORT. Peek shut down at 8:22 PM ET; iPad (A16) stayed Shutdown.

| Run | Window (ET) | JIT budget / L1 | Cold launch | first_paint_ms | Scroll fps (frames, p95 ms) | Input key / click ms | Warm Δup / nav_ms | Shared insert / evict (max) | Peak RSS |
| --- | --- | --- | ---: | ---: | --- | --- | --- | --- | ---: |
| CR simdef-cr-1 | 8:01–8:04 PM | default (1G/256M) | 22.95 s | 2195.6 | 1.92 (5, 883.1) | ok, 184.5 / 144.2 | 5.99 s / 3689 | 3.09M / 3.09M (105792 B) | 2744 MiB |
| FF simdef-ff-1 | 8:05–8:07 PM | default (1G/256M) | 46.82 s | 46.0 | 28.00 (56, 199.9) | ok, 504.3 / 333.0 | 4.63 s / 2406 | 3.76M / 3.76M (105792 B) | 2917 MiB |
| CR sim4G-cr-1 | 8:08–8:10 PM | **4G/128M** | **9.24 s** | 730.7 | **18.39** (37, 250.0) | ok, 27.9 / 44.9 | **0.82 s** / 530 | 1.38M / 15k (3 GiB) | 3448 MiB |
| CR sim4G-cr-2 | 8:11–8:13 PM | **4G/128M** | **8.92 s** | 563.3 | **16.83** (34, 379.4) | ok, 34.4 / 42.7 | **0.69 s** / 481 | 1.37M / 3k | 3536 MiB |
| FF sim4G-ff-1 | 8:14–8:16 PM | **4G/128M** | **19.77 s** | 4.0 | **54.12** (115, 17.4) | ok, 6.0 / 91.3 | **2.01 s** / 1118 | 1.44M / 261k | 3827 MiB |
| FF sim4G-ff-2 | 8:17–8:20 PM | **4G/128M** | **20.50 s** | 34.0 | **50.36** (101, 33.3) | ok, 23.0 / 220.0 | **2.05 s** / 0 | 1.44M / 261k | 3776 MiB |

The Simulator default was worse than D4iPad: the 1 GiB default whole
budget is eaten by eight private L1s, the shared tier is 105,792 bytes,
and **every** insertion is evicted (no cross-process reuse of libxul /
libchrome translations). At 4G/128M: Chromium cold 23.0→8.9–9.2 s, scroll
1.9→16.8–18.4 fps, warm second page 6.0→0.7–0.8 s, key/click 185/144 →
28–34/43–45 ms; Firefox cold 46.8→19.8–20.5 s, scroll 28→50–54 fps, warm
4.6→2.0 s. (Peak RSS is the sampled app process only; Peek itself holds
several GiB.) **Landed: `launch-sim-0022-test.sh` now defaults to
4G/128M** (`JIT_BUDGET=default` restores the binary default).

### Summary vs uml-darwin official 0022 (two-run ranges)

| Metric | uml-darwin | D4iPad 2G (before) | D4iPad 4G | Sim default (before) | Sim 4G |
| --- | --- | --- | --- | --- | --- |
| Chromium cold launch | 7.5–7.6 s | 21.6–22.1 s | **8.5–8.7 s** | 23.0 s | **8.9–9.2 s** |
| Chromium scroll fps | 9.25–9.47 | 3.31 (1 stall) | 9.4–12.9 | 1.92 | 16.8–18.4 |
| Chromium warm 2nd page | 0.60–0.64 s | 3.56 s | 0.60–0.74 s | 5.99 s | 0.69–0.82 s |
| Firefox cold launch | 15.8–15.9 s | 38.8–40.2 s | **18.5–18.7 s** | 46.8 s | **19.8–20.5 s** |
| Firefox scroll fps | 40.7–42.2 | 34.7–48.9 | 48.3–52.2 | 28.0 | 50.4–54.1 |
| Firefox warm 2nd page | 1.16–1.19 s | 2.9–3.3 s | 1.8–2.0 s | 4.6 s | 2.0 s |

The Chromium cold-launch gap is closed to within ~1–1.7 s of uml-darwin
on both iOS targets; the remaining Firefox gap is ~3–5 s, and Firefox
still evicts ~0.23–0.26M entries at 3 GiB shared (a 6G budget is the next
probe; not run because D4iPad RSS is already ~5.7 GiB on the 16 GB mini).
The int2-cr-1 stall at 2G (guest at 0.2% CPU from SCROLL_START) did not
recur at 4G.

## Can a real iPhone afford JIT 4G + mem=4G? (13 Nov 2026, 8:24 PM ET onward)

Nothing was installed on any phone. Research plus D4iPad measurement only.

**iOS per-app limit.** jetsam enforces a per-process `phys_footprint`
(dirty + compressed memory, IOSurface/Metal included), not a virtual-size
limit. The Kernarium app already carries `com.apple.security.cs.allow-jit`,
`com.apple.developer.kernel.increased-memory-limit` and
`com.apple.developer.kernel.extended-virtual-addressing`. Public
measurements (Apple Developer Forums thread 834805, Nov 2026) put the
live ceiling (`os_proc_available_memory()` + `phys_footprint`) at about
**6144 MB on an 8 GB iPhone 16 Pro Max** with increased-memory-limit, with
no change from extended-virtual-addressing. Other reports range from
~6–7 GB on 8 GB phones; without the entitlement it is ~3.3 GB. Extended
virtual addressing only buys address space for reservations (the 8 GiB
`VM_ALLOCATE` reservation below), not resident budget. Plan for ≤ ~5.5 GB
footprint on a 16 Pro to leave headroom; the iPhone Duo's RAM/limit is not
public, so assume the same until measured with `os_proc_available_memory()`.

**How the JIT memory is backed (0022 source).** The shared translation
tier (`jit_shared_translations.cpp`) is ordinary heap (`MALLOC_SMALL`):
resident as soon as a translation is published, charged against the budget
with a deliberately conservative per-entry formula (2× vector growth,
16 bucket pointers, 8 allocator allowances), so `accounted` overstates
real bytes. Eviction is a clock sweep in guest-PC order over unpinned
entries, then pinned ones; it is not LRU. Per-executor code arenas sit in
the large `VM_ALLOCATE` reservation (virtual) and only the touched pages
are resident. Guest RAM (`mem=4G`) is `shared memory`, resident only as the
guest touches it; Linux page cache will grow it toward 4 GiB in a long
session.

**Measured (D4iPad Chromium, 4G/128M, run fp4G-cr-1, 8:25–8:28 PM ET,
`footprint` every 5 s and `vmmap -summary` every 30 s;
`scripts/macos-metal/footprint-sampler.sh`).** Timing for that run was
cold 8.77 s, warm 0.68 s; scroll 5.5 fps is perturbed by the vmmap pause.

| Region (vmmap at t=91 s) | Virtual | Resident | Compressed | Meaning |
| --- | ---: | ---: | ---: | --- |
| MALLOC_SMALL | 2.5G | 1.7G | 815M | JIT shared tier (payload 1.94 GB, accounted 3.22 GB) + other heap |
| shared memory | 3.1G | 2.2G | 80K | guest RAM actually touched (of mem=4G) |
| VM_ALLOCATE | 8.0G | 263M | 19M | JIT arenas / reservations (mostly virtual) |
| MALLOC_LARGE | 438M | 181M | 12M | other heap |
| IOSurface + IOAccelerator | 75M | 73M | 72M | Metal display |
| **TOTAL footprint** | 17.0G | 5.4G | 0.95G | `phys_footprint` 5.0–5.4 GB, peak 5401 MB |

So the 4G budget's real cost is ~2.5 GB for the shared tier (resident +
compressed), not 3 GiB, plus guest RAM. Peak 5.4 GB is under a ~6.1 GB
16 Pro ceiling but leaves < 0.8 GB, and guest page cache growth toward
mem=4G (+~1.8 GB) would cross it. A phone configuration needs a smaller
shared tier and/or a smaller guest. Sweep below.

### Smaller budgets backfire on footprint (D4iPad sweep, 8:29–8:48 PM ET, one run each, footprint sampled)

| Run | Window (ET) | Budget / L1 | Cold | Scroll fps | Warm Δup | Shared insert / evict | Payload | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | --- | ---: | ---: |
| CR fp4G-cr-1 | 8:25–8:28 PM | 4G/128M | 8.77 s | 5.5* | 0.68 s | 1.39M / 20k | 1849 MB | **5401 MB** |
| CR sw3G-128M-cr-1 | 8:29–8:32 PM | 3G/128M | 10.36 s | 0.9* | 2.39 s | 1.60M / 0.70M | 1233 MB | 5645 MB |
| FF sw3G-128M-ff-1 | 8:32–8:35 PM | 3G/128M | 27.76 s | 43.9 | 2.57 s | 1.67M / 0.91M | 1349 MB | 6544 MB |
| CR sw2560M-128M-cr-1 | 8:35–8:38 PM | 2.5G/128M | 16.50 s | 2.2* | 2.97 s | 1.82M / 1.16M | 927 MB | 5999 MB |
| FF sw2560M-128M-ff-1 | 8:38–8:41 PM | 2.5G/128M | 33.43 s | 47.8 | 2.43 s | 1.95M / 1.40M | 1013 MB | 7069 MB |
| CR sw3G-64M-cr-1 | 8:42–8:44 PM | 3G/64M | 9.55 s | 7.9 | 1.94 s | 1.48M / 0.34M | 1542 MB | **4740 MB** |
| FF sw3G-64M-ff-1 | 8:45–8:47 PM | 3G/64M | 28.94 s | 47.5 | 2.50 s | 1.59M / 0.62M | 1682 MB | 5600 MB |

\*Scroll numbers in footprint runs are perturbed by the 30 s `vmmap`
task suspension; cold launch and warm are not (vmmap first runs ~25 s
after app start).

The surprise: shrinking the shared tier *raises* footprint. `vmmap` shows
`MALLOC_SMALL` dirty at 2.4–3.2 GB (plus 0.6–0.8 GB compressed) for 2.5G
and 3G while live payload is only 0.9–1.3 GB. Eviction churn leaves the
publish arena fragmented: a `TranslationPublishChunk` is only released
when every entry in it is evicted (clock order is by guest PC, not by
chunk), so freed bytes stay dirty. Less churn (4G) means fewer orphaned
partial chunks. Halving the private L1 cap (64M) cut footprint ~0.9 GB at
the same 3G whole budget.

### Private L1 cap, guest size and a lean-Firefox try (D4iPad, 8:48–9:07 PM ET)

| Run | Window (ET) | Budget / L1 / guest | Cold | Scroll fps | Warm Δup | Shared insert / evict | Payload | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | --- | ---: | ---: |
| CR sw4G-64M-g4096-cr-1 | 8:48–8:51 PM | 4G/64M/4096 | **9.10 s** | 8.95 | 0.91 s | 1.40M / **0** | 1886 MB | **4696 MB** |
| CR sw4G-64M-g3072-cr-1 | 9:01–9:04 PM | 4G/64M/3072 | **9.21 s** | 8.79 | 0.91 s | 1.40M / **0** | 1889 MB | **4639 MB** |
| FF sw4G-128M-g4096-ff-1 | 8:55–8:57 PM | 4G/128M/4096 | 20.27 s | 56.7 | 1.84 s | 1.42M / 237k | 2018 MB | **6014 MB** |
| FF sw4G-64M-g4096-ff-1 | 8:51–8:54 PM | 4G/64M/4096 | 26.36 s | 53.9 | 1.90 s | 1.43M / 37k | 2344 MB | 5397 MB |
| FF sw4G-64M-g3072-ff-1 | 9:04–9:07 PM | 4G/64M/3072 | 26.22 s | 54.7 | 1.89 s | 1.45M / 61k | 2347 MB | 5368 MB |
| FF lean sw4G-64M-g4096-fflean-1 | 8:58–9:01 PM | 4G/64M/4096 | 29.60 s | 53.5 | 1.86 s | 1.40M / 7k | 2337 MB | 5255 MB |

- **Chromium fits a phone at 4G/64M.** Cold 9.1–9.2 s (vs 8.5–8.8 s at
  128M and 7.5 s uml-darwin), warm 0.9 s, zero shared evictions, peak
  footprint 4.6–4.7 GB: ~1.4 GB under a ~6.1 GB 16 Pro ceiling.
- **Firefox at the Mac default (4G/128M) peaks at 6.0 GB**: too close to
  the 16 Pro ceiling. 4G/64M brings it to 5.4 GB but cold launch slips
  20→26 s; a 64M L1 holds less of Firefox's hot working set, so it
  re-materializes from the shared tier (Chromium does not care).
- **Guest 3072 MiB** changes nothing in these short sessions (the guest
  touches ~1.7–2.4 GB here) but caps long-session page-cache growth at
  ~1 GB less, which is what keeps a phone under the line over time.
- **Lean Firefox** (`/usr/local/etc/firefox-lean`: no Fission, 1 content
  process, no prelaunch, in-process socket/extensions) saves ~0.15 GB but
  is slower (29.6 s). Not landed; the opt-in stays in
  `firefox-kernarium-profile.sh` and `EXTRA_ETC=firefox-lean` in the bake.

**Phone profile (recommended, not a Mac default change):** JIT 4G whole /
64M L1, guest 3072 MiB. Mac D4iPad and Sim keep 4G/128M/4096 for speed.
The next lever is in the JIT itself, not the budget: charge the 1 MiB
`TranslationPublishChunk` residency (not just per-entry payload) to the
budget so it is a true footprint cap, evict chunk-coherently (or age-based)
so chunks empty, and `madvise(MADV_FREE)` free-listed chunks. That would
let a smaller budget keep the win instead of inflating `MALLOC_SMALL`.
Not attempted here; it needs a Kernarium change and an iOS runtime rebuild.

### Simulator phone-profile check (Peek, 9:09–9:13 PM ET)

| Run | Window (ET) | Budget / L1 / guest | Cold | Scroll fps | Key / click ms | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | --- | ---: | ---: | ---: |
| CR simphone-cr-1 | 9:09:56–9:12:51 PM | 4G/64M/3072 | 10.24 s | 11.90 | 27.2 / 53.6 | 1.10 s | 0 | **4243 MB** |

(Sim 4G/128M/4096 was 8.9–9.2 s cold, 16.8–18.4 fps.) The matching
Firefox run was cut off by an interruption at 9:14 PM ET and is rerun
below. Cleanup at 9:14 PM ET: the Sim batch, its xcodebuild/app and the
footprint sampler were stopped and Peek shut down; no uml-darwin, lldb
or LaunchAgent left; official 0022 md5 unchanged.

### Smallest budget that keeps the win (D4iPad, guest 3072, 9:14–9:21 PM ET)

| Run | Window (ET) | Budget / L1 / guest | Cold | Scroll fps | Warm Δup | Shared evict | Payload | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CR sw3584M-64M-g3072-cr-1 | 9:14:55–9:17:46 PM | 3.5G/64M/3072 | **9.26 s** | 8.35 | 1.01 s | 30k | 1848 MB | **4639 MB** |
| FF sw3584M-64M-g3072-ff-1 | 9:18:05–9:20:55 PM | 3.5G/64M/3072 | 26.86 s | 49.3 | 2.07 s | 306k | 2014 MB | **5425 MB** |

3.5G/64M matches 4G/64M (CR 9.1–9.2 s / 4.6–4.7 GB; FF 26.2–26.4 s /
5.4 GB) and beats 3G/64M (CR 9.55 s / 4.74 GB, FF 28.9 s / 5.60 GB), so
**3584M / 64M L1 / guest 3072 MiB is the smallest phone profile that keeps
the win.** Chromium has ~1.5 GB headroom under ~6.1 GB; Firefox only ~0.7 GB,
so on a 16 Pro Firefox is marginal and Chromium is the browser to ship.
**Landed as the iOS-target default** in `launch-d4ipad-0022.sh`,
`bootstrap-d4ipad-0022.sh`, `run-d4ipad-interactive.sh` and
`launch-sim-0022-test.sh` (override with `4G 128M 4096` for the faster
Mac-only profile, whose Firefox peaks at 6.0 GB).

### Phone-profile confirmation at launcher defaults (3584M/64M/3072)

| Run | Window (ET) | Cold | Scroll fps | Key / click ms | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: |
| D4iPad CR def-cr-2 | 9:22:06–9:24:55 PM | **9.09 s** | 10.99 | 26.2 / 59.4 | 0.93 s | 33k | **4626 MB** |
| D4iPad FF def-ff-2 | 9:25:13–9:27:59 PM | 26.92 s | 49.72 | 393.0 / 142.0 | 2.22 s | 313k | **5403 MB** |

Both D4iPad configs reproduce the 9:14–9:21 PM pair (CR 9.26 s / 4639 MB,
FF 26.86 s / 5425 MB). Note: commit `5b19b76` accidentally included the
local-only `scripts/macos-metal/vnc_rfb.py`; `7b305ef` untracked it again
(file kept locally, no secrets in it). It remains in pushed history unless
David approves a history rewrite.

#### Simulator phone-profile confirmation

| Run | Window (ET) | Cold | Scroll fps | Key / click ms | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: |
| Sim CR simphone-cr-2 | 9:35:10–9:37:54 PM | **9.64 s** | 14.70 | 22.2 / 69.4 | 0.96 s | 24k | **4240 MB** |
| Sim FF simphone-ff-1 | 9:28:43–9:31:41 PM | 29.13 s | 44.88 | 119.5 / 186.0 | 2.40 s | 335k | **5024 MB** |
| Sim FF simphone-ff-2 | 9:31:59–9:34:52 PM | 27.17 s | 48.65 | 91.0 / 199.0 | 2.14 s | 322k | **5001 MB** |

Simulator rows are at launcher defaults (env shows 3584M / 64M / guest
3072). With simphone-cr-1 (10.24 s, 4243 MB) the Sim phone profile gives
Chromium 9.6–10.2 s at 4.24 GB and Firefox 27–29 s at 5.0 GB. Peek booted
9:28 PM, shut down 9:38 PM ET; iPad (A16) Shutdown throughout; swap
822.94M, no SWAP_ABORT; no leftover processes; official 0022 md5
`6ea8180e05fc6736d32530811ba3c439`.

## JIT shared tier: free publications, chunk budget, chunk-coherent eviction (branch only, 13 Nov 2026, 9:40 PM ET onward)

Kernarium branch `exclusive/0022-chunk-evict` (local only, never pushed), off
`exclusive/0022-clean` 9676ead. Commit 1720a1b (9:5x PM ET).

**Root cause found first: shared publications were never freed.** A packed
publication's `guest_words` member was an owning alias of the publication's
own control block (`shared_ptr{owner, guest}`), i.e. a self-reference. Its
count never reached zero, so no `SharedTranslation` destructor ran, no arena
chunk's `live` hit 0, and no chunk ever reached the freelist. "Eviction" only
removed index entries; resident shared-tier memory was every translation
ever published. That is why smaller budgets *raised* footprint (more churn =
more republication = more leaked chunks). Unit test before the fix:
874 evictions, 0 chunks returned; after: 2000 evictions, 16 returned.

Fix + new mode:
- `guest_words` is now a non-owning alias; the three L1 sites that keep the
  words (`saved_guest_words`) pin via `owned_guest_words(translation)`
  (aliasing the translation's control block). Unused test: `use_count()==1`.
- Chunk budget (default in `instance()`; `KERNARIUM_/UML_JIT_SHARED_CHUNK_BUDGET=0`
  turns it off): budget = index overhead + committed 1 MiB chunks
  (process-wide). Over budget, `reclaim_chunks` evicts every cache entry of
  the coldest retired chunk (min last-hit tick, then oldest), up to 16 chunks
  per insert; the PC clock sweep runs only for an explicit shard cap.
- Chunks are mmap'd; an emptied chunk gets `madvise(MADV_FREE_REUSABLE)`
  (drops out of phys_footprint at once), `MADV_FREE_REUSE` on reuse.
- Stats line adds `chunk_mode arena_committed arena_free chunks_taken
  chunks_returned chunk_evictions`.
- New unit test `arm64-jit-shared-translation-chunks` (8 MiB budget, 2760
  publications: committed peak 7 MiB, hot chunk kept, cold chunk evicted, pin
  survives eviction). Note: `arm64-jit-shared-translation-cache` does not
  compile on 0022-clean already (it still uses vector APIs on the span fields).

Second commit 166fb47: **L1s copy shared validation words instead of
pinning the publication.** With the cycle fixed, each L1 block's
`saved_guest_words` pin still kept a whole 1 MiB chunk resident after the
shared tier evicted it. Charged to the budget, that starved chunk mode
(156k rejections, matches 193k -> 29k in the 128M check below). The identity
prefix now goes into the way's preallocated fallback buffer (the path
private compiles already use), so evicted chunks drain at once.

Side binary `uml-darwin-0022-chunk-20261113` (md5
`68483c61286771bfc5750d7f8c6d267b`, in the clean tree's
macos-integration bin; clean `uml-darwin` restored to `6ea8180e…`).
Official `uml-darwin` / `uml-darwin-official-0022-20261113` untouched
(`6ea8180e05fc6736d32530811ba3c439`).

Checks (all ET, 13 Nov):
- Unit: new `arm64-jit-shared-translation-chunks` PASS. arm64-jit ctest
  53/61 pass; the 8 failures (memory-preparation, runtime,
  reservation_alias, indirect-link-runtime, chain-abi-codegen/runtime,
  fp-link-runtime, sme-mode) fail identically on 0022-clean 9676ead.
  shared-translation-cache / persistent-translation-cache / cache_validation
  tests do not compile on 9676ead either.
- hello PASS 10:03:11 PM; atomic-stress (8 x 200k, mem=2G) PASS
  10:03:13–10:03:33 PM.
- Tight budget atomic-stress (`--jit-cache-budget=1152M
  --jit-executor-cache-budget=128M`, shared tier 128M), all PASS:

| Run (ET) | Binary / mode | Wall | Peak RSS | Shared matches | Evictions | Committed chunks at exit | Chunks returned |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 9:59:08–9:59:32 PM | official 0022 | 24 s | 1867 MiB | 193,323 | 217,316 | (never freed) | 0 |
| 10:02:10–10:02:34 PM | chunk mode | 24 s | **1515 MiB** | 144,951 | 254,407 | **95 MiB** | 495 |
| 10:02:34–10:02:59 PM | leak fix only (`CHUNK_BUDGET=0`, PC sweep) | 25 s | 1917 MiB | 193,105 | 217,075 | 498 MiB | **0** |

  The PC-order sweep never empties a chunk even with the cycle fixed, so
  chunk-coherent eviction is what actually returns memory.
- uml-darwin desktop (labwc Metal 1920x1080, mem=4G, 8G budget, persist off):

| Run (ET) | Binary | Cold launch | Scroll | Warm 2nd page | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| CR 10:12:27–10:12:49 PM | chunk | 7.78 s | 8.37 fps | 0.64 s | 4021 MiB |
| FF 10:13:08–10:13:41 PM | chunk | 15.63 s | 10.96 fps (outlier) | 0.99 s | 5069 MiB |
| FF 10:13:51–10:14:24 PM | official 0022 | 15.66 s | 42.46 fps | 1.30 s | 5432 MiB |
| FF 10:14:40–10:15:14 PM | chunk | 16.20 s | 48.69 fps | 0.87 s | 5271 MiB |
| FF 10:15:14–10:15:47 PM | chunk binary, mode off | 15.99 s | 40.38 fps | 0.96 s | 5666 MiB |

  Reference earlier today: Chromium 7.50–7.62 s, Firefox 15.74–15.91 s.
  No cold or warm loss; at 8G nothing is evicted, so the mac gain is small.

iOS runtime rebuild with the branch: started 10:17 PM ET (official runtime
xcframework APFS-cloned to `scratch/KRuntime_6_18_4K.xcframework.official0022`).

D4iPad, chunk runtime, phone default 3584M/64M/3072 (first pass, 10:21–10:37 PM ET):
Chromium 22:21–22:24 cold 9.42 s / scroll 6.95 fps / warm 0.98 s, footprint not
sampled (app relaunched after the rebuild, rerun pending); Firefox 22:25–22:27
cold 26.29 s / scroll 53.97 fps / warm 1.78 s, peak phys_footprint **5044 MB**
vs official 5403 MB / 26.92 s (index 751 MB, arena committed 2468 MB, 300 chunk
evictions). 3G Chromium (22:28) stalled after an evdev write (guest 0.1% CPU,
same as the earlier official 2G stall); serial saved, app stopped ~22:37.

### Unit test aborts fixed (Kernarium `exclusive/0022-chunk-evict` 827bb51, 13 Nov 2026, 10:30–10:56 PM ET)

The 8 aborting arm64-jit tests fail identically on 9676ead (the campaign
patches, not the chunk code). Test-only updates, results still checked:

- memory-preparation: macOS/Sim hosts use the host JIT route, so `ready`
  (and the pair published) or `unsupported` are both accepted.
- runtime: a read-only invocation now links into the store block; the loop
  runs to the chain bound (x2 = limit/4, then limit/2; replacement add #2
  gives 2*(limit/4)).
- reservation_alias: with branch continuation the untaken retry reaches a
  following `svc`; `continued` or `system_call` accepted (passes unchanged
  with `UML_JIT_NO_BRANCH_CONTINUE=1`).
- indirect-link-runtime: the evicted first target hits the executor-wide A64
  target table (syscall, x0 = 11, misses 3 / trains 3); the missing native FP
  environment case now drops the environment (`restore_native_fp_environment`)
  before the run and still falls back.
- fp-link / chain-abi-runtime: FP state is materialized before every native
  entry and read-only sources link into store targets, so those links run to
  the system call (vector and stored values checked); the untaken
  conditional continues to the svc.
- chain-abi-codegen: SUBS + early budget exit, a link-record flag `tbz`;
  direct path 12 words, PIC path 35 (site ways + A64 table); all exits share
  the cold undo.
- sme-mode: the test helper reports only link relocations (guest_pc slots
  hold raw addresses).

`ctest -R ^arm64-jit`: 61/61 pass; the 3 pre-existing compile breaks
(shared-translation-cache, persistent-translation-cache, cache_validation)
are unchanged.

### Firefox scroll re-check, uml-darwin chunk vs official (alternating, 10:57–11:01 PM ET)

| Run (ET) | Binary | Cold | Scroll | Warm | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: |
| 10:57:53 PM | chunk 68483c61 | 16.44 s | 43.41 fps | 0.87 s | 4831 MiB |
| 10:58:32 PM | official 6ea8180e | 15.96 s | 38.89 fps | 0.91 s | 5128 MiB |
| 10:59:10 PM | chunk | 15.98 s | 41.68 fps | 1.08 s | 5087 MiB |
| 10:59:49 PM | official | 15.49 s | 41.93 fps | 1.07 s | 5276 MiB |
| 11:00:28 PM | chunk | 16.46 s | 39.44 fps | 1.49 s | 5109 MiB |
| 11:01:07 PM | official | 15.61 s | 41.25 fps | 1.23 s | 5278 MiB |

No scroll regression: the 10.96 fps run was an outlier (chunk 39.4–48.7 over
4 runs, official 38.9–42.5). Peak RSS is 170–450 MiB lower. Cold is a little
slower on the mac: chunk 15.63–16.46 s (mean 16.14 over 5) vs official
15.49–15.96 s (mean 15.68 over 4), about +3%. Swap unchanged at 791 MiB.

### D4iPad stall root cause: stats-dump deadlock (harness-only), fixed on the branch (64d6c34)

D4iPad CR sw3584M-64M-g3072-ckcr-2 (11:02 PM ET) froze at Chromium launch
(0.5% CPU, phys_footprint flat at 3406 MB for 7 min). `sample` showed
every vCPU in `install_shared_translation` → `shared_mutex::lock_shared`
and one in the periodic `dump_shared_translation_stats`. `find()` called
that dump while still holding its shard shared; `statistics()` takes every
shard shared again, which queues behind a waiting writer and deadlocks.
The dump only runs with `UML_JIT_SHARED_STATS=1`, which all our launchers
set, and the same code is in official 9676ead, so this probably also
explains the earlier official 2G and the chunk 3G stalls. Fix: release the
shard lock before dumping. arm64-jit ctest 61/61 again; device runtime
rebuilt 11:17 PM ET. Sample and serials saved:
`notes/ios-interactive/d4ipad-sw3584M-64M-g3072-ckcr-2-*stalled-20261113-231111*`.
Stopped cleanly at 11:11 PM ET (sweep killed, LaunchAgent booted out).

### D4iPad chunk runtime vs official, phone default 3584M/64M/3072 (summary, 11:25 PM ET)

| Run | Window (ET) | Runtime | Cold | Scroll fps | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| CR def-cr-2 | 9:22–9:24 PM | official 0022 | 9.09 s | 10.99 | 0.93 s | 33k | 4626 MB |
| CR sw…-cr-1 | 9:14–9:17 PM | official 0022 | 9.26 s | 8.35 | 1.01 s | 30k | 4639 MB |
| CR ckcr-1 | 10:21–10:24 PM | chunk 166fb47 | 9.42 s | 6.95 | 0.98 s | 0 | not sampled |
| CR ckcr-2 | 11:02–11:11 PM | chunk 166fb47 | stalled (stats deadlock) | — | — | 0 | 3411 MB (frozen) |
| CR ckcr-3 | 11:17–11:20 PM | chunk + fix 64d6c34 | 9.33 s | 9.33 | 0.94 s | 0 | not sampled |
| FF def-ff-2 | 9:25–9:27 PM | official 0022 | 26.92 s | 49.72 | 2.22 s | 313k | 5403 MB |
| FF sw…-ff-1 | 9:18–9:20 PM | official 0022 | 26.86 s | 49.3 | 2.07 s | 306k | 5425 MB |
| FF ckff-1 | 10:25–10:27 PM | chunk 166fb47 | 26.29 s | 53.97 | 1.78 s | 160k | **5044 MB** |
| CR 3G/64M ckcr-1 | 10:28–10:36 PM | chunk 166fb47 | stalled | — | — | — | — |

- The 3G/64M row is the "10:36 PM host stall" (xcodebuild exit 65, guest
  143). That was me stopping the frozen run, not a host fault. It is the
  same stats-dump deadlock as ckcr-2 (the guest sat at 0.1% CPU after an
  evdev write).
- The footprint sampler misses the first run after a runtime rebuild because
  the app relaunches and the PID changes. ckcr-1 and ckcr-3 have no peak
  `phys_footprint` for that reason.
- So far, Firefox is about 360–380 MB lower (5044 vs 5403–5425 MB) with no
  cold loss. Chromium cold is within noise (9.33–9.42 vs 9.09–9.26 s), and its
  footprint is still unmeasured. That is one Firefox run, so it is **not yet
  a clear win and has not landed**. The Sim runtime has not been rebuilt.
- The interrupt at 11:20 PM ET stopped the sweep before ckff-2 started:
  sweep killed, LaunchAgent booted out, nothing left running. Mini health
  at 11:21 PM ET: memory free 73%, swap 791/2048 MiB (unchanged all
  evening), load 4.6. No Simulator booted, no xcodebuild/lldb/uml-darwin
  running. Official uml-darwin and uml-darwin-official-0022-20261113
  are md5 6ea8180e. The D4iPad xcframework currently holds the
  chunk+fix runtime. The official one is backed up at
  `scratch/KRuntime_6_18_4K.xcframework.official0022`.

### D4iPad chunk+fix 64d6c34, phone default, footprint sampler re-resolves PID (682e457) — 13/14 Nov 2026 overnight

| Run | Window (ET) | Cold | Scroll fps | Key / click ms | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: |
| FF ckff-2 | 11:23:28–11:26:17 PM | 24.91 s | 52.43 | 211.0 / 100.0 | 2.05 s | 165k | **5049 MB** |
| CR ckcr-5 | 11:26:59–11:29:48 PM | 9.28 s | 10.43 | 20.5 / 48.5 | 0.83 s | 0 | **4744 MB** (official 4626–4639) |
| FF ckff-3 | 11:30:29–11:33:16 PM | 25.28 s | 47.19 | 82.0 / 135.0 | 1.62 s | 174k | **5075 MB** |
| CR ckcr-6 | 11:33:57–11:36:47 PM | 9.19 s | 7.47 | 29.2 / 56.4 | 0.96 s | 0 | **4705 MB** |

D4iPad verdict: Firefox 5049–5075 MB vs official 5403–5425 MB (**−330 to
−376 MB**), cold 24.9–25.3 s vs 26.9 s. Chromium 4705–4744 MB vs official
4626–4639 MB (**+66 to +118 MB**), cold 9.19–9.28 s vs 9.09–9.26 s.
Chromium never evicts at 3.5G, so chunk charging only adds arena slack.
Footprint is not lower on both browsers, so chunk mode is **not** a clear
win and does not become the iOS default.

#### Simulator (Peek) chunk+fix 64d6c34, phone default 3584M/64M/3072 (Sim runtime rebuilt 11:38 PM ET; Peek booted 11:39 PM)

| Run | Window (ET) | Cold | Scroll fps | Key / click ms | Warm Δup | Peak `phys_footprint` |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| Sim FF simck-ff-1 | 11:39:49–11:43:30 PM | 26.49 s | 51.60 | 162.0 / 77.3 | 2.24 s | **4663 MB** (official 5001–5024, 27.2–29.1 s) |

(The sampler re-resolved the app PID at t=60 s: 41084 → 41631.)
| Sim CR simck-cr-1 | 11:44:00–11:46:45 PM | 9.48 s | 12.48 | 25.7 / 59.7 | 0.90 s | **4317 MB** (official 4240–4243, 9.6–10.2 s) |

Peek shut down 11:47 PM ET.

#### Verdict and restore (11:47–11:50 PM ET)

| Profile | Browser | Official peak fp | Chunk+fix peak fp | Δ | Cold official → chunk |
| --- | --- | ---: | ---: | ---: | --- |
| D4iPad | Firefox | 5403–5425 MB | 5049–5075 MB | −330…−376 MB | 26.9 → 24.9–25.3 s |
| D4iPad | Chromium | 4626–4639 MB | 4705–4744 MB | +66…+118 MB | 9.09–9.26 → 9.19–9.28 s |
| Sim | Firefox | 5001–5024 MB | 4663 MB | −338…−361 MB | 27.2–29.1 → 26.5 s |
| Sim | Chromium | 4240–4243 MB | 4317 MB | +74…+77 MB | 9.6–10.2 → 9.5 s |

Chunk mode is a large Firefox win with no speed loss, but Chromium (which
never evicts at 3.5G) costs 70–120 MB more. Footprint is not lower on both
browsers, so it is **not landed**:
- The official runtime is restored in `kernarium-xcframeworks` from
  `scratch/KRuntime_6_18_4K.xcframework.official0022` (device md5
  `78ac5040…`, sim `97092f94…`, no chunk symbols). The chunk+fix
  xcframework is kept at `scratch/KRuntime_6_18_4K.xcframework.chunk64d6c34`.
- The Simulator app was rebuilt with the official runtime (embedded md5
  `97092f94`). The D4iPad app re-embeds the restored framework on its next
  launch, because the launcher always runs xcodebuild.
- The `Kernarium-0022-clean` worktree is switched back to
  `exclusive/0022-clean` 9676ead, with the 7 local overlays kept.
- Nothing was pushed. The only Kernarium remote is upstream imxieyi; there
  is no fork remote.
- Candidate correctness fix on the official line: branch
  `exclusive/0022-statsfix` f4cd2c7, which is 9676ead plus the stats-dump
  deadlock fix only. It has not been built or run as a binary. A syntax
  check against the official headers shows no new diagnostics. Official
  binaries are unchanged (md5 `6ea8180e`).
- Probable next step: charge chunks only once the shared tier is near its
  cap, or return the open chunk's slack. That would remove the Chromium
  overhead.

## Hybrid shared-tier budget (Kernarium `exclusive/0022-chunk-hybrid` 6c186ff off 64d6c34, 14 Nov 2026, ~12:00 AM ET onward)

Why chunk mode cost Chromium memory: the byte budget over-charges about
1.65x payload. Official CR hits its 3.22 GB cap (payload 1.94 GB) and
evicts about 30k entries. Chunk charging counts the true committed arena
(2.22 GB + 0.82 GB index), stays under the cap, and evicts nothing, so it
keeps about 70–120 MB more.

Hybrid keeps the byte charges. Past 90% of the cap
(`UML_JIT_SHARED_CHUNK_EVICT_PCT`), a publisher evicts up to 4 coldest
whole chunks after its insert, with one reclaimer at a time and outside the
shard lock. A full tier reclaims whole chunks first, then falls back to the
PC sweep. `UML_JIT_SHARED_CHUNK_BUDGET=0` gives the byte budget and `1/full`
gives the old whole-chunk charging. New unit test
`hybrid_keeps_byte_charges_until_the_threshold_then_evicts_chunks` (first
crossing at 818 entries, 49 chunk evictions, accounted ≤ cap, 83 chunks
returned, hot entries kept). arm64-jit ctest 61/61.

### D4iPad hybrid 6c186ff, phone default 3584M/64M/3072 (device runtime md5 2555dcdf, built 11:57 PM ET)

| Run | Window (ET) | Cold | Scroll fps | Key / click ms | Warm Δup | Shared evict | Chunk evict | Peak `phys_footprint` |
| --- | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| CR hycr-1 | 11:57:08 PM–12:00:33 AM | **11.96 s** | 10.97 | 53.7 / 65.1 | 0.99 s | 185k | 316 | **4430 MB** |
| FF hyff-1 | 12:01:17–12:04:09 AM | 26.69 s | 45.76 | 84.5 / 112.0 | 1.89 s | 411k | 666 | **4626 MB** |
| CR hycr-2 | 12:04:50–12:07:35 AM | 9.41 s | 7.90 | 28.5 / 74.3 | 1.05 s | 159k | — | **4409 MB** |
| FF hyff-2 | 12:08:17–12:11:04 AM | 26.13 s | 44.45 | 334.0 / 133.0 | 2.10 s | 415k | — | **4626 MB** |
| CR hycr-3 | 12:11:45–12:14:37 AM | 9.30 s | 7.61 | 24.3 / 58.4 | 0.99 s | 157k | — | **4398 MB** |

hycr-1 was the first run after the rebuild (the app relaunched, PID
55207 → 55958), and its 11.96 s cold is an outlier; hycr-3 was the
tiebreak.

| Browser | Official peak fp / cold / scroll | Hybrid peak fp / cold / scroll | Δ footprint |
| --- | --- | --- | ---: |
| Chromium | 4626–4639 MB / 9.09–9.26 s / 8.4–11.0 | 4398–4409 MB / 9.30–9.41 s / 7.6–7.9 (plus 4430 MB, 11.96 s outlier) | **−220 to −240 MB** |
| Firefox | 5403–5425 MB / 26.86–26.92 s / 49.3–49.7 | 4626 MB ×2 / 26.13–26.69 s / 44.5–45.8 | **−777 to −799 MB** |

Hybrid lowers footprint a lot on both browsers, and cold/warm are within
noise. But Firefox scroll is 9–11% below official (and below chunk mode's
47–54) on both runs, and Chromium cold is +0.1–0.3 s. Evictions are
157–185k on CR and 411–415k on FF, against official 30k / 313k. So
**speed is not clearly "no worse", and hybrid does not land** by the
round's rule. Next lever: a 95% threshold, or evict only toward 90% from a
95% trigger, to cut churn.

### Statsfix-only candidate f4cd2c7 (official 0022 plus the deadlock fix), D4iPad sanity

| Run | Window (ET) | Cold | Scroll fps | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| CR sfcr-1 | 12:15:52–12:19:08 AM | 9.39 s | 8.67 | 0.85 s | 32k | 4629 MB |

The device runtime was built from f4cd2c7 at 12:15 AM ET (md5 9900b530, no
chunk symbols). `UML_JIT_SHARED_STATS=1` was on through the launcher, and
116 periodic stats dumps were written with no freeze. Footprint and
eviction match official (4626–4639 MB, 30–33k). Official binaries are not
replaced.

Restore at 12:19 AM ET: the official xcframework is back from the backup
(device 78ac5040, sim 97092f94). The worktree is back on
`exclusive/0022-clean` 9676ead with its 7 overlays. The D4iPad app
re-embeds the official runtime on its next launch, and the Sim app is
already official (97092f94). Scratch is cleaned: the chunk xcframework
copy, ab-ff.sh, the old sampler copy and the /tmp plists are gone.
Mini at 12:19 AM ET: memory free 74%, swap 775/2048 MiB, no SWAP_ABORT,
nothing running, Peek shut down. Official uml-darwin md5 is 6ea8180e.
Kernarium is not pushed.

## Hybrid high/low-water (95/90) round (14 Nov 2026, 12:20 AM ET onward)

| Run | Window (ET) | Runtime | Cold | Scroll fps | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| FF offf-1 (same-session baseline) | 12:27:13–12:30:04 AM | official 78ac5040 | 24.62 s | **50.90** | 2.04 s | 307k | 5385 MB |
| FF hlff-1 (95/90, 9a2cd70, first after rebuild) | 12:36:38–12:39:57 AM | a1c04956 | 26.29 s | 47.70 | 1.91 s | 411k | 4704 MB |
| FF hlff-2 (95/90) | 12:41:50–12:44:38 AM | a1c04956 | 26.09 s | 47.44 | 1.98 s | 408k | 4595 MB |

95/90 still over-evicts on Firefox (408–411k vs official 307k) and scroll is
−6–7% vs the same-session baseline, so the Firefox gate fails; Chromium not run
at 95/90. Moving to 97/93.

Kernarium ea13662 (defaults 97/93; tests 61/61 + chunk test pass), runtime md5 20643a83.

| Run | Window (ET) | Runtime | Cold | Scroll fps | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| FF h97ff-1 (first after rebuild) | 12:47:52–12:51:11 AM | 20643a83 | 25.32 s | 52.77 | 1.97 s | 320k | 4754 MB |
| FF h97ff-2 | 12:51:31–12:54:18 AM | 20643a83 | 25.78 s | 52.10 | 1.94 s | 318k | 4776 MB |
| CR h97cr-1 | 12:55:08–12:57:57 AM | 20643a83 | 9.40 s | 10.92 | 0.99 s | 133k | 4597 MB |
| CR h97cr-2 | 12:58:53–1:01:38 AM | 20643a83 | 9.16 s | 8.41 | 0.89 s | 134k | 4593 MB |

Reference: official FF offf-1 (same session) 24.62 s / 50.90 fps / 2.04 s /
5385 MB; earlier official FF ff-1 26.86 s / 49.30 / 2.07 s / 5425 MB;
official CR cr-1 (9:14 PM) 9.26 s / 8.35 / 1.01 s / 4639 MB (range 4626–4639).

**Verdict: landed as the D4iPad (iOS device) default.** 97/93 no longer
over-evicts Firefox (318–320k vs official 307k; 95/90 was 408–411k). Footprint
is lower on both browsers: Firefox −610 to −630 MB, Chromium −30 to −46 MB.
Firefox scroll 52.1–52.8 vs 50.9 (+3–4%), cold 25.3–25.8 s (inside the official
24.6–26.9 s spread), warm 1.94–1.97 vs 2.04 s. Chromium cold 9.16–9.40 vs
9.09–9.26 s, scroll 8.4–10.9 vs 8.35, warm 0.89–0.99 vs 1.01 s. The Chromium
footprint win is small but consistent across both runs.

- The D4iPad xcframework now has the hybrid 97/93 device slice (md5 20643a83,
  Kernarium ea13662, local branch `exclusive/0022-chunk-hybrid`, not pushed)
  and the official Sim slice (97092f94, unchanged). Official xcframework backup
  stays at `scratch/KRuntime_6_18_4K.xcframework.official0022` (device 78ac5040)
  for rollback.
- Official `uml-darwin` and `uml-darwin-official-0022-20261113` are untouched
  (md5 6ea8180e).
- Mini at 1:03 AM ET: swap 767/2048 MiB, memory 72% free, no Simulator booted,
  nothing running. Scratch cleaned.

(The 12:20–12:26 AM attempts were refused by the preflight because my
wrapper's own pgrep pattern matched "uml-darwin". Nothing else was running.)

Kernarium 9a2cd70 on `exclusive/0022-chunk-hybrid` (local only): evict at
95%, drain to 90% (`UML_JIT_SHARED_CHUNK_EVICT_PCT` / `_LOW_PCT`). Chunk
test + arm64-jit ctest 61/61 pass.

## Sim hybrid 97/93 round (14 Nov 2026, 1:03 AM ET onward)

Peek iPhone 17 Simulator, phone default 3584M/64M, guest 3072 MiB, one run at a
time, footprint via `footprint-sampler.sh` (wrapper `sim-one.sh`).

The first official baseline attempt (1:05 AM) failed to build in 10 s: the
D4iPad packaging had left MesaEGL/MesaGallium/HostBattery/HostVideoEncoder
device-only. Re-ran `package-ios-linux-device-and-simulator.sh` and put the
landed KRuntime back (device hybrid 20643a83, Sim official 97092f94).

| Run | Window (ET) | Sim runtime | Cold | Scroll fps | Warm Δup | Shared evict | Peak `phys_footprint` |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| FF simoff-ff-1 (same-session baseline, first after app rebuild) | 1:10:08–1:13:46 AM | official 97092f94 | 28.43 s | 51.66 | 2.52 s | 327k | 5013 MB |
| FF simh97-ff-1 (hybrid ea13662, first after rebuild) | 1:15:44–1:19:10 AM | hybrid 0415aeb3 | 27.74 s | 48.31 | 2.26 s | 391k | 4408 MB |
| FF simh97-ff-2 | 1:19:28–1:22:14 AM | hybrid 0415aeb3 | 26.92 s | 48.40 | 2.28 s | 321k | 4398 MB |
| CR simh97-cr-1 | 1:23:55–1:26:41 AM | hybrid 0415aeb3 | 9.71 s | 14.46 | 0.93 s | 62k | 4208 MB |
| CR simh97-cr-2 | 1:26:59–1:29:42 AM | hybrid 0415aeb3 | 9.63 s | 20.74 | 0.83 s | 62k | 4213 MB |

Earlier official Sim references (13 Nov, same phone default): FF simphone-ff-1/2
29.13 / 27.17 s, scroll 44.88 / 48.65, warm 2.40 / 2.14 s, 5024 / 5001 MB; CR
simphone-cr-1/2 10.24 / 9.64 s, scroll 11.90 / 14.70, warm 1.10 / 0.96 s,
4243 / 4240 MB.

**Verdict: landed as the Sim default.** Footprint is lower on both browsers:
Firefox −600 to −615 MB against the same-session baseline, Chromium −27 to
−35 MB against the official runs. Firefox scroll 48.3–48.4 is 6% under the
single same-session baseline (51.66), but sits in the middle of the official
Sim spread (44.9–51.7, mean 48.4) and well clear of the D4iPad 95/90 failure
pattern (there every run was below every official run). Firefox cold
26.9–27.7 s vs official 27.2–29.1 s (28.4 same session); warm 2.26–2.28 vs
2.14–2.52 s. Chromium cold 9.63–9.71 vs 9.64–10.24 s, scroll 14.5–20.7 vs
11.9–14.7, warm 0.83–0.93 vs 0.96–1.10 s. Shared evictions return to the
official level (FF 321–391k vs 327k).

- KRuntime xcframework: device hybrid 20643a83, Sim hybrid 0415aeb3 (both
  Kernarium ea13662, local only). The Sim app in `kernarium-simulator-derived`
  embeds 0415aeb3. Rollback: `scratch/KRuntime_6_18_4K.xcframework.official0022`
  (device 78ac5040, Sim 97092f94), then rebuild the Sim app.
- Packaging note: `build-d4ipad-0022.sh` leaves MesaEGL, MesaGallium,
  HostBattery and HostVideoEncoder device-only, which breaks Sim builds. Run
  `package-ios-linux-device-and-simulator.sh` (or `build-sim-0022.sh`) after any
  D4iPad build. All xcframeworks now carry both slices except KosmicKrisp
  (device-only by design).
- Official `uml-darwin` and `uml-darwin-official-0022-20261113` untouched (md5
  6ea8180e). Peek shut down at 1:30 AM ET. Mini at 1:31 AM ET: swap 767/2048
  MiB, memory 71% free, nothing running. Scratch cleaned. New helper
  `notes/ios-interactive/sim-one.sh TAG ff|cr`. Stopped for the night.

## crate vs Kernarium on the Mac mini (14 Nov 2026, 8:30–9:20 AM ET)

[oneamendez/crate](https://github.com/oneamendez/crate) is an arm64-to-arm64
full-system translator (MPL-2.0). It was built from source at commit
`bd2efb4ae9d8567d581b1e6c2313ac21a112f1f2` (v0.1.1, 14 Nov 2026 12:28 AM ET)
and benchmarked against official `uml-darwin` 0022 (md5 6ea8180e). Same
interactive page, the same markers and the same parser formulas as
`measure-interactive.sh`. One VM at a time, with the swap guard on.
Harness: `scripts/crate-compare/`. Raw logs: Google Drive
`crate-vs-kernarium-bench-20261114.tgz`.

### Security skim (before building)
- **Dependencies:** only `libc`, `flate2`/`miniz_oxide`, `adler2`, `cfg-if` and
  `simd-adler32` from crates.io, verified by the Cargo.lock checksums
  (`--locked`).
- **build.rs:** the one `build.rs` (crate-host) runs only `pkg-config
  --variable=libdir slirp` and then links libslirp.
- **Network:** no outbound network code. The only sockets are the VNC
  listener (a Unix socket, or TCP that defaults to 127.0.0.1) and slirp
  port-forwards bound to 127.0.0.1.
- **Signing:** `tools/crate-run/build.sh` runs `cargo build` plus an ad hoc
  codesign with the `com.apple.security.hypervisor` entitlement. Nothing else.
- **Fetch scripts:** none was run. The image was fetched by hand from the
  `arm64-desktop-images` catalog (release 2026.11.14-7, which points at the
  2026.11.14-4 debian-xfce assets). The kernel, initrd, the xz part and the
  decompressed disk all matched the catalog's SHA-256s.
- **GPU fetch scripts (not run):** crate-ios `fetch-frameworks.sh` pulls a
  pinned, SHA-checked iOS zip. `build-angle.sh` clones depot_tools and ANGLE,
  and `build-virgl.sh` curls libepoxy and virglrenderer tarballs.
- **Toolchain:** `brew install libslirp` (4.9.7) was the only change to the mini.

### Setup and differences
- **Mac build:** crate-run built in 6 s (rustc 1.99.1). The Mac needs a
  macOS ANGLE plus virglrenderer, and the published scripts build only iOS
  frameworks. A depot_tools and ANGLE build on 12 GB of free disk is well over
  an hour, so crate ran with `--display 2d`. The guest therefore renders in
  software (Firefox SWGL, Chromium software compositing). **Kernarium runs
  virgl to the host GPU (Zink/KosmicKrisp)**, so the GPU comparison favours
  Kernarium.
- **crate config:** `--backend jit` (never hvf), `--cpus 4 --memory 4096`,
  `--modes 1920x1080`, slirp networking, VNC on a Unix socket.
- **crate guest:** Debian 13 Xfce (X11, LightDM autologin) on a stock Debian
  6.12 kernel, booted with a NoCloud seed ISO (user, temporary SSH key).
  Browsers: Debian `firefox-esr` 153.7.0esr and `chromium` 156.0.8078.79.
- **Kernarium config:** official 0022 `uml-darwin` through
  `measure-interactive.sh` with only `ncpus=4` changed (a copy,
  `measure-interactive-crate-cmp.sh`). Guest 4G, at 4G/128M and at 8G JIT
  budget.
- **Kernarium guest:** Alpine 3.24.2 labwc (Wayland) with the
  `starter-20261112` images and Alpine's Firefox and Chromium.
- **Architecture:** UML runs the guest kernel natively on the host and JITs
  only EL0, one cache per address space. crate translates everything (EL1 too)
  behind an inline soft-TLB.
- **Same in both:** the page and the markers, and the Firefox `user.js` and
  Chromium flags from `desktop-guest/`. A real key and click are injected
  (VNC on crate, evdev on Kernarium). The browser is maximized (wmctrl on
  crate, the labwc rule on Kernarium). Each run is a fresh VM, a cold browser
  profile and a cold translation cache.
- **Boot to desktop:** host seconds from launch to `===DESKTOP_READY===`
  (crate: an Xfce autostart entry; Kernarium: the labwc start script).

### Results (medians, with the range across runs)

| Run set | Window (ET) | Boot→desktop | Cold page load | Scroll fps | Warm 2nd page |
| --- | --- | ---: | ---: | ---: | ---: |
| crate FF ×6 (crff-3..8) | 8:43–8:48 AM | 7.38 s (7.35–7.43) | **13.9 s** (10.1–14.1) | **0.3** (0.29–18.6)¹ | 0.82 s (0.60–1.00) |
| crate CR ×3 (crcr-1..3) | 8:48–8:50 AM | 7.28 s (7.20–7.46) | **3.82 s** (3.46–4.03) | **54.7** (53.9–55.6) | **0.47 s** (0.40–0.48) |
| Kernarium FF 4G/128M ×2 | 8:50–8:52 AM | 3.64 s (2.83–4.45) | 15.8 s (15.7–16.0) | 35.1 (29.5–40.8) | 1.23 s (1.18–1.28) |
| Kernarium CR 4G/128M ×2 | 8:52–8:54 AM | 3.30 s (2.94–3.66) | 6.96 s (6.47–7.44) | 11.5 (10.9–12.1) | 0.63 s (0.61–0.65) |
| Kernarium FF 8G ×2 | 8:54–8:56 AM | 3.29 s (3.25–3.34) | 16.6 s (16.1–17.0) | 38.7 (34.1–43.4) | 1.14 s (0.93–1.35) |
| Kernarium CR 8G ×2 | 8:54–8:57 AM | 3.83 s (3.76–3.90) | 7.83 s (7.82–7.85) | 13.5 (13.3–13.7) | 0.74 s (0.71–0.78) |

¹ crate Firefox's first scroll pass had a single 2.8–3.5 s frame in five of
six runs. The page's first rAF fires before the content is painted (a
screenshot at that point shows a blank page). Re-opening the page in the same
browser (supplemental pass) gave 42.1 and 38.4 fps for Firefox and 59.9–60.8
fps for Chromium. Kernarium has no such pass, and its first pass is already
29–43 fps. crff-1/2 (8:40–8:42 AM, window not yet maximized) are left out:
13.1 s cold, 0.2 fps.

Input latency (event to the next rAF):
- **crate:** Chromium 3–13 ms; Firefox 14–34 ms (key) and 15–56 ms (click).
- **Kernarium:** Chromium 9–32 ms; Firefox key 2–173 ms, click 57–206 ms.

### CPU-bound (bonus; `cmp-benches.sh`, the same script in both guests, 4 CPUs)
crate's own workload scripts are not published, so these are equivalents.
Each tool's output hash matches between the two guests.

| Workload | crate jit (Debian) | Kernarium 4G/128M (Alpine) | Ratio |
| --- | ---: | ---: | ---: |
| gcc -O2, 600-function generated file | 12.5 s | 54.3–56.3 s | 4.4× |
| gcc again | 12.4–12.5 s | 55.6–56.5 s | 4.5× |
| `node -e 0` | 0.20–0.41 s | 0.36–0.44 s | ~1.2× |
| node integer loop (1e8) | 1.07–1.21 s | 1.52–1.60 s | 1.4× |
| node float loop (3e7 sqrt) | 0.90–1.06 s | 1.74 s | 1.8× |
| python loop (3e6) | 1.16–1.24 s | 2.75–2.79 s | 2.3× |
| 1000 `/bin/true` spawns | 0.85–0.86 s | 3.63–4.63 s | 4.8× |

- **Tool versions differ:** gcc 14.2 vs 15.2, node 20.19 vs 24.22, python
  3.13 vs 3.14.
- **Not comparable:** the awk and sha256 rows (10.4 s and 0.94 s on
  Kernarium) measure busybox against mawk/coreutils, not the translator.
- **Windows:** crate ran 9:00–9:02 AM ET. Kernarium kcpu-1 ran 9:12–9:18 AM
  ET; an earlier attempt at 9:01 AM failed because the guest script was not
  executable.

### Verdict
**On this mini, crate gives the more usable desktop for Chromium, and it is
far faster on CPU-bound and process-heavy work.**
- **Chromium:** cold load is 1.8–2× faster, scroll is 4–5× faster even in
  software rendering, and the warm page is about 35% faster.
- **Firefox:** cold load is about 2 s faster, but the first scroll pass stalls
  for 3 s while the first real paint lands. Once painted, steady scroll is
  about level with Kernarium's GPU path.
- **Boot:** Kernarium boots to a desktop about 2× faster (3.3 s vs 7.4 s). It
  starts a minimal Alpine labwc on a native host kernel, where crate boots
  full Debian with systemd, LightDM and Xfce.
- **Why:** the gap tracks process creation and code reuse. Kernarium compiles
  every exec'd process's code again, which shows in spawn ×4.8, gcc ×4.4 (cc1
  and as are fresh processes each time) and the multi-process browsers'
  launch. crate translates once per physical page. Pure loops differ much
  less (node ×1.4), which is where register residency and return prediction
  show.

### crate techniques and whether they port to Kernarium's JIT (rough expected gains)
1. **Page-keyed translations (one per physical page, PC = run-time page base
   plus offset).** The biggest win. Kernarium's private cache is keyed per
   address space, and the shared tier keys by guest PC, which ASLR defeats.
   Keying by the backing page (the UML page cache or file frame) would let
   exec'd processes reuse libc, libxul, libchrome and cc1 translations.
   - **Expected gain:** 2–4× on spawn/exec-heavy work, 1.5–3× on gcc, and
     about 30–50% off browser cold launch (Chromium's 7 s is mostly
     per-process translation).
   - **Effort:** high. Code must be position-independent (ADR/ADRP and
     literals relative to `page_va`), invalidation must be per frame, and it
     needs guarded chaining (item 2).
2. **Guarded cross-page chaining** (a key of the target VA XOR a context
   number). It is only needed together with item 1, because Kernarium's links
   are already per address space.
   - **Expected gain:** about 5–10% of cycles on top of item 1 (crate measured
     8–12% on gcc).
3. **BL-based return prediction** (a host BL into a tail, then the return
   continuation translated as an entry, and RET through the host return
   stack). Kernarium lowers RET as an indirect site: two inline cells plus an
   8K table, steered by the indirect predictor.
   - **Expected gain:** about 5–10% on call-heavy code (compilers, JS and
     Python interpreters).
   - **Effort:** moderate. It touches block-ending rules and the link
     contract.
4. **Register identity mapping** (guest Xn in host Xn, with X15–X17 as
   scratch and X18 kept in state). Kernarium's A64 keeps 8 resident slots with
   per-block allocation and spills.
   - **Expected gain:** about 10–20% on tight integer and SIMD loops (node and
     python loops are 1.4–2.3× slower today, partly for this reason).
   - **Effort:** high. Every helper and host call must save or restore, and it
     conflicts with x19–x21 linked-block state.
   - **Lower-cost alternative:** widen residency to around 16 slots first.

The inline soft-TLB and the per-CPU code caches are already in Kernarium in
other forms, and nothing about them suggests a large gain.

### Cleanup
- **Mini scratch:** `scratch/crate-bench` deleted (3.8 GB: the crate clone and
  build, the cargo home, the 5 GB sparse Debian disk, the seed ISO and the
  temporary SSH key), plus the temporary `measure-interactive-crate-cmp.sh`
  in interactive-pack.
- **Mini health at 9:20 AM ET:** 13 GiB free, swap 528/2048 MiB, no VM
  running, no Simulator booted.
- **Official binaries untouched:** `uml-darwin` and
  `uml-darwin-official-0022-20261113` (6ea8180e), and the iOS runtimes
  (device 20643a83, Sim 0415aeb3).
- **Left in place:** Homebrew libslirp.

## Porting crate's ideas into Kernarium: step 0, profile first (14 Nov 2026, 9:36 AM ET onward)

The rules haven't changed:
- Kernarium work stays on local branches and is never pushed.
- The official `uml-darwin`/`uml-darwin-official-0022-20261113` (md5 6ea8180e) and the iOS runtimes stay untouched.
- One VM runs at a time, with the preflight and swap guard on.

crate is MPL-2.0, so I reimplement from the ideas in its `docs/DESIGN.md` and copy none of its code.

**Harness.** `scratch/jitprof/` on the mini (copied to `scripts/kernarium-port/`). It boots the official 0022 binary on the slim Alpine image at `mem=4G ncpus=4` with a 4G/128M budget and gcc from the offline apks. The guest prints `===PHASE===` markers, and the host snapshots the `UML_JIT_PROFILE` counters (plus `UML_JIT_SIGPROF` at 999 Hz, or `UML_JIT_SHARED_STATS`) at each marker. Each phase runs first with ASLR on (`randomize_va_space=2`), then with it off (`=0`). Runs: p0-official-jit 9:38–9:43 AM, p0-official-sp (SIGPROF) 9:43–9:48 AM, p0-spawn-stats 9:48–9:50 AM ET.

### Spawn: where the time goes (seconds per 1000, guest uptime)

| Phase | ASLR on | ASLR off | Compiles / iteration (on) | Shared-tier reuses / iteration (on) |
| --- | ---: | ---: | ---: | ---: |
| fork + `_exit` (static C spawner) | 0.21 | 0.20 | 0 | ~0.3 |
| fork + exec of a static no-libc binary | 0.28 | 0.25 | 0 | ~0 |
| fork + exec `/bin/true` (busybox, musl) from a static parent | 1.39 | 1.58 | 1.4 | 586 |
| busybox `sh` loop: `/bin/true` (**the bench**) | **3.61** | **1.94–2.05** | **545** | 178 |
| busybox `sh` loop: static binary | 0.78 | 0.77 | 0 | ~400 |
| busybox `sh` loop: subshell `(:)` (fork only) | 1.20 | 1.23 | 3 | 411 |
| static parent exec'ing a `#!/bin/sh` script that runs `/bin/true` (×300) | **8.33** | **1.35** | **1376** | 631 |

For reference, crate's whole `sh` loop is 0.85 s.

Answers to the three candidates:
1. **UML's own fork/exec/mm cost is small.**
   - A fork is 0.2 ms and an exec of a static binary another 0.07 ms.
   - The whole `sh` loop around a static binary is 0.78 ms per iteration, about crate's total for the dynamic one.
   - Host syscalls, TLB and page-table work never rank in the SIGPROF top 20: `madvise`, `mmap` and `mach_vm_map` together are under 2%.
2. **Retranslation is the biggest cost under ASLR, and it is a bug, not a design limit.**
   - Kernarium already has a page-keyed tier. It looks a translation up by the backing physical page's stamp plus page offset, with a slide relocation, so the same libc/busybox page can be reused at another ASLR base. That is why a static parent exec'ing `/bin/true` compiles almost nothing (586 location-key reuses per exec).
   - But the location key also includes the page's **version**, and `unmap_locked()` bumps the version of every executable page with a translation whenever such a mapping is torn down. A forked busybox `sh` child maps busybox's frames with their code bits copied from the parent. When it execs, it moves every busybox text page's version, so the next `/bin/true` at a new random base misses the location index and compiles about 545 blocks again.
   - `UML_JIT_SHARED_STATS` confirms it: location matches grow by about 4k while misses grow by 545k in that phase. With ASLR off the same-VA key (no version) hits, and the loop drops from 3.6 to 2.0 s.
   - The version is not needed for correctness here. Both lookups compare the exact guest instruction words the translation consumed (`matches_guest_prefix`), the same check the same-VA key relies on.
3. **Once nothing recompiles, the next cost is per-process materialization.** Every new address space (fork or exec) starts with an empty private cache. It copies each block's template out of the shared tier (585 blocks for one `/bin/true`, 411 for a forked shell), patches its relocations, creates link records and flushes the icache.
   - SIGPROF in the static-parent `/bin/true` phase, with profiler I/O excluded: memmove 30%, link-table create/find 16%, `sys_icache_invalidate` 14%, shared find/validate 8%, translated guest code only 8%.
   - This is the part crate avoids: its code cache is per CPU and keyed by physical page, with `page_va` plus offset at run time, so a new process installs nothing.

### gcc -O2 (big.c, 56–59 s): not translation

| gcc phase | Wall | Compiles | Compile time | Shared reuses | Dispatcher exits (indirect miss / continued) | Guest instructions |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| first, ASLR on | 56.5 s | 2,518 | 10 ms | 113k | 9.96M / 18.3M | 35.3 G |
| again, ASLR on | 56.8 s | 4,040 | 12 ms | 1.63M | 8.73M / 17.0M | 29.2 G |
| first, ASLR off | 58.1 s | 208 | 2 ms | 140k | 9.59M / 17.8M | 34.4 G |

Translation is about 0.02% of gcc. SIGPROF over the gcc phase, excluding profiler I/O and symbolization:
- **Translated code:** ~55%.
- **Dispatcher round trips:** ~20%. This is `JitExecutor::find`, `run_block`, the indirect link table and `train_indirect`: about 27M exits per run, mostly indirect-branch misses (returns and calls through tables) and chain breaks (`continued`: uncompiled 2.5M, fairness budget 2.5M, non-link 2.0M, unsafe 0.9M).
- **Guest page work:** memset/madvise ~6%. The UML kernel itself is a few percent; `svc` is 340k per run and page faults 640k.

crate runs the same file in 12.5 s, so gcc's 4.4× gap is in how fast translated code runs and how often it leaves to the dispatcher. That points at crate's return prediction and register identity mapping, not at page keys.

### Plan from the profile
1. **Location key without version.** Key the page-keyed tier by (backing frame identity, page offset) and keep validating the exact guest words. This targets the spawn gap that comes from recompiling. Expected: the `sh` loop drops from 3.6 to ~2.0 s, and the script-spawning case from 8.3 to ~1.4 s.
2. **Return prediction** (host BL plus a return stub that RETs to a predicted entry), to cut indirect exits on gcc.
3. **More resident guest registers.**

I'll consider the larger per-CPU, physically keyed, run-time position-independent code cache (crate's "install once") only after step 1 has been measured, because it changes the link-ownership contract (links are per address space).

## Step 1: shared tier keyed by backing page + offset, without the version (branch `port/page-key`)

Commits on the local Kernarium branch `port/page-key` (off ea13662, never pushed):
- `d9d496f`: `location_key()` drops the frame version by default (`UML_JIT_SHARED_LOCATION_VERSION=1` puts it back). The words are still compared on reuse, so a recycled frame with different code still misses. Each location bucket is capped at 8 entries.
- `9e63203`: the location offset comes from `key_fetch_address(pc)` and keeps the AArch32/Thumb/TBI mode bits. Without this, T32 keys (`pc << 1`) aliased, and the AArch32 corpus had 12 exclusive-pair failures; with it the corpus shows 0. Adds a unit test for the unversioned index.

This is crate's idea (one translation per backing page, reused at any VA by slid relocations) applied to Kernarium's existing tier. Kernarium already had the position-independent part (slides). What it lacked was surviving the version bump on `unmap`. The cross-page chaining is unchanged: it was already guarded by the record's key and epoch.

Gates (binary `uml-darwin-port-pk2`, md5 2df9b681): JIT unit tests 61/61 (the 3 suites that don't build were already broken before this branch); hello PASS; atomic-stress 8×200k PASS.

Spawn microbench, s per 1000 (ASLR on, 4 CPU / 4G):

| phase | official | pk1 |
|---|---:|---:|
| sh loop of /bin/true | 3.61 | 2.11 |
| script ×300 (sh -c true) | 8.33 | 1.54 |
| fork, fork+exec static, subshell | unchanged (noise) | |
| compiles per iteration | ~545 | ~0 |

CPU A/B (`cmp-benches.sh`, same session, 4 CPU):

| bench | official | pk2 |
|---|---:|---:|
| gcc -O2 big.c | 58.85 / 58.30 | 58.59 / 58.48 |
| spawn_1000 | 4.03 | 2.37 / 2.34 |
| node int / fp | 1.62 / 1.71 | 1.60 / 1.73 |
| python / awk / sha | 2.81 / 11.14 / 0.95 | 2.82 / 10.59 / 0.95 |

Spawn is 1.7× faster. gcc is flat; that was expected, since gcc is exec/dispatch-bound, not translation-bound.

## Step 2: A64 return-address stack (Kernarium `port/page-key` a7df85b)

This is crate's "BL/RET through the host return stack" idea, built from Kernarium's own parts as a software stack, because guest returns must keep the budget and epoch checks:
- `JitReturnStack`: a 32-entry ring of `JitBlockLink*` per executor. `JitChainState.return_stack` sits at offset 64, so the state is now 72 bytes.
- A64 BL and BLR push the stable link record of `pc+4`, resolved at compile time and relocated as `direct_link`, so shared templates slide.
- RET pops the top entry and enters it only if the record's `activation_epoch` equals the chain epoch AND `record.guest_pc == tag|target`. Otherwise it falls through to the existing 2-cell site and the A64 table.
- The ordinary linked-entry checks (budget, selector, internal entry) still run. A stale or bad entry costs one miss and never runs wrong code.
- `UML_JIT_NO_RETURN_STACK=1` turns it off. AArch32 is unchanged.
- The profile build also counts indirect-miss kinds (ret, blr, br, other).

Gates (uml-darwin-port-rs1, md5 3cda186a): JIT unit tests 61/61, hello PASS, atomic-stress PASS.

| bench (4 CPU) | official | step 1 (pk2) | step 2 (rs1) |
|---|---:|---:|---:|
| gcc -O2 | 57.6–58.9 | 57.9–58.6 | 55.6–56.7 |
| spawn_1000 | 4.03 / 4.93 | 2.34 / 2.37 | 2.53 / 2.54 |
| python | 2.60–2.81 | 2.82–2.90 | 2.69–3.04 |
| awk | 10.57–11.14 | 10.56–10.59 | 10.71–10.82 |

gcc is about 4% faster. The other benches are within noise.

## Desktop browser gate for steps 1 and 2 (Chromium is the primary target), 14 Nov 10:51–11:15 AM ET

Setup: `k-measure.sh`, 4 CPU / 4G, budget 4G/128M, runs alternated one at a time. "cold" is the time from CHROMIUM_START to first paint of the interactive page. "scroll" is fps.

| binary | Chromium cold (s) | mean | Chromium scroll fps (mean) |
|---|---|---:|---:|
| official 0022 | 7.31 6.64 6.27 6.53 6.17 7.04 6.71 6.44 | **6.64** | 12.9 |
| step 1 (pk2) | 8.41 6.95 6.79 6.69 8.18 7.76 7.52 | **7.47** | 12.2 |
| step 1+2 (rs1) | 8.33 7.95 8.57 | **8.28** | 12.3 |
| rs1 with `UML_JIT_NO_RETURN_STACK=1` | 7.53 7.35 | 7.44 | 12.7 |

Firefox, 2 runs each:
- cold: official 16.50 / 15.45 vs rs1 16.81 / 16.97
- scroll: official 37.2 / 36.3 vs rs1 25.4 / 40.2 (noisy)

**Both steps make Chromium cold start worse.**

Step 1 adds about 0.8 s (bimodal: some runs match official, others are about 1.5 s slower). Shared stats for one Chromium run each:

| | location reuses | misses |
|---|---:|---:|
| official | 0.90M | 1.29M |
| pk2 | 2.36M | 0.89M |

So step 1 does compile about 30% less. Even so, the SIGPROF profile shows more `_platform_memmove` (+44%, from materializing slid templates) and more psynch mutex/cv time, and less compile time. In Kernarium, compiling is cheap (the compile/emit bucket is under 1% of samples). For Chromium, reusing a template by location therefore saves little, and costs memmove plus contention on shared-tier locks across 4 vCPUs. The spawn microbench still gains 1.7×, because there the saved work is about 545 compiles per exec of a tiny process.

Step 2 adds another 0.8 s, and spawn_1000 goes 2.35 → 2.53. Each A64 BL now carries an extra `direct_link` relocation for the return record. Every compile, and every materialization into a new address space, has to resolve it (find_or_create in the link table). That costs in the compile-heavy and spawn-heavy cases, and pays off only in long-running gcc (about 4%).

Decision so far: neither step lands as a default. Both stay on the branch behind knobs.

## Step 3: dispatch cost for gcc (fairness budget). Register pinning was tried and dropped. 14 Nov 11:17 AM–11:35 AM ET

**Register pinning (tried, dropped).** I let A64 translations bind all 15 host GPRs (x22–x28 are callee-saved, using the extended frame) instead of 8. Results:
- gcc: 55.6–56.9 s, the same as rs1.
- spawn: 2.46–2.53.
- It broke 6 exact-shape codegen tests.

Register pressure inside blocks is not where gcc's time goes, so I reverted it. True cross-link pinning for A64 would mean porting the A32 `keep_gprs_across_links` scheme to a fixed 31→N map, with flushes at every helper. That is a large change for a cost the profile does not show.

**Fairness budget (the dispatch lever).** Step 0's gcc profile showed 29M dispatcher exits per run, 5.1M of them from the 4096-instruction fairness budget. Each one is a full exit to C++ and a re-entry through the prologue. Kernarium commit `e10b990` raises the budget to 16384.

| bench (4 CPU) | official 0022 | pk2 + budget 16384 (fb1) |
|---|---:|---:|
| gcc -O2 | 57.6 / 58.1 / 58.3 / 58.9 | 55.4 / 54.4 / 54.8 / 55.1 |
| spawn_1000 | 4.03 / 4.93 | 2.22 / 2.30 |
| python / awk | 2.60–2.81 / 10.6–11.1 | 2.51–2.71 / 10.4 |

Chromium cold start:
- Budget only (fb1 with the versioned key, `UML_JIT_SHARED_LOCATION_VERSION=1`): 7.85 6.37 6.34 6.59 6.50, median 6.50.
- Official (n=10): median 6.48.
- So budget-only is at parity with official on Chromium.
- fb1 with the unversioned key: mean 7.54. The step-1 regression is still there.

**Candidate default (c1):** versioned key (step 1 opt-in via `UML_JIT_SHARED_LOCATION_UNVERSIONED=1`), return stack opt-in (`UML_JIT_RETURN_STACK=1`), budget 16384.

Kernarium commits (local branch `port/page-key`): `3ac159b`, `e0a89c4`, `e10b990`.

## Candidate c1 gate on uml-darwin (Kernarium `port/page-key` e9ecad6), 14 Nov 11:40–11:56 AM ET

c1 = official ea13662 base + chain budget 16384. Steps 1 and 2 are compiled in but opt-in only. Binary md5 61531481.

Gates:
- JIT unit tests 61/61 by default, and 61/61 with `UML_JIT_RETURN_STACK=1`. Tests that hard-coded the 4096 budget were updated in e9ecad6.
- hello PASS, atomic-stress PASS.

Chromium (primary target), 4 CPU / 4G:

| | cold s | mean | scroll fps mean |
|---|---|---:|---:|
| official (n=11, 10:51–11:51) | 6.17–7.31 | 6.56 | 12.8 |
| c1 (n=5) | 6.51 6.29 6.50 7.43 7.21 | 6.79 | 12.7 |

Firefox:

| | cold s | scroll fps |
|---|---|---|
| official (n=3) | 16.50 15.45 16.42 | 37.2 36.3 41.8 |
| c1 (n=3) | 17.26 15.75 15.91 | 46.3 29.1 35.0 |

CPU, separate session (11:40 AM ET):
- gcc 57.2 / 57.2 / 57.6 / 56.6.
- spawn_1000 3.83 / 4.38 (back to the official level, as expected with step 1 off).
- A same-session c1-vs-official A/B is running to settle gcc.

Browsers are at parity within noise. This is not yet a clear win.


## Candidate c1 gcc A/B, same session (14 Nov 2026, 11:59 AM–12:08 PM ET)

`cpu-ab.sh cpu6`: c1 first (`uml-darwin-port-c1`, md5 61531481, Kernarium `port/page-key` e9ecad6), then official 0022 (`uml-darwin-official-0022-20261113`, md5 6ea8180e). Same harness as before: slim Alpine, 4 CPU / 4G, budget 4G/128M, `cmp-benches.sh` twice per VM. No other VM was running. Swap stayed at 520/2048 MiB; no SWAP_ABORT.

| bench | c1 (cpu6-a, 11:59:33–12:04:11) | official 0022 (cpu6-b, 12:04:11–12:08:59) |
| --- | --- | --- |
| gcc -O2 | 56.36 / 56.14 / 55.69 / 55.66 | 58.17 / 57.15 / 57.95 / 58.03 |
| spawn_1000 | 3.73 / 4.31 | 3.71 / 4.77 |
| node int | 1.62 / 1.53 | 1.62 / 1.55 |
| node fp | 1.74 / 1.67 | 1.71 / 1.71 |
| python | 3.06 / 2.56 | 2.79 / 2.53 |
| awk | 10.51 / 10.49 | 10.44 / 10.39 |
| sha256 50MB | 0.92 / 0.92 | 0.96 / 0.93 |

gcc mean: c1 **55.96 s** vs official **57.83 s**, **3.2% faster** (medians 55.92 vs 57.99, 3.6%). The earlier "~6%" figure was fb1 (budget 16384 plus the unversioned key still on by default) against official numbers from mixed earlier sessions. c1 is budget-only; this same-session A/B is the one to trust.

The other benches are at parity, including spawn (step 1 is opt-in, so that is expected). Combined with the 11:40–11:56 AM browser gate (Chromium cold 6.79 vs 6.56, scroll 12.7 vs 12.8; Firefox cold and scroll inside the official spread), **c1 is a modest gcc win at browser parity. It is not a clear net win on the primary target (Chromium is flat), so it does not by itself justify a D4iPad default change.** Official `uml-darwin` (6ea8180e) and the iOS runtimes are untouched. Kernarium is not pushed.

Next: why steps 1 and 2 regress Chromium cold, and whether a variant keeps the 1.7× spawn win without that cost.


## Why steps 1 and 2 regress Chromium, and a sharded-index variant (c2) that keeps the spawn win (14 Nov 2026, 12:09–12:32 PM ET)

### Cause (from the existing SIGPROF / shared-stats logs, then a same-session A/B)

It is not location-key lookup cost, and it is not shared-tier cache pressure.

- `LocationKey` hash find was 1.5% of SIGPROF samples on official and 1.3% on step 1 (pk2). Slightly cheaper, not more expensive.
- Evictions were 0 on both Chromium runs. At first paint, pk2 had *fewer* shared entries (745k vs 1.08M) and a smaller payload (1037 vs 1534 MB).
- Shared stats at first paint (st-off-cr vs st-pk2-cr): official location hits 489k / misses 1.09M; pk2 location hits 1.36M / misses 0.75M, and same-VA hits fell (1.17M vs 1.71M) because the second Chromium process now finds a slid template instead of compiling under its own VA.

The cost is a lock convoy plus extra template copies:

- SIGPROF over the Chromium run: locks/sync **41.7% → 52.0%**, memmove **9.2% → 12.3%**. malloc (compiling) fell 3.2% → 1.3%.
- The same-VA directory is already 64-way sharded (padded mutexes) because one lock "serialised [executors] into a convoy that cost more than the compilation it saved." The location index still had a **single** `locations_mutex_`, under a comment that "lookups are compile-path only, so one mutex is enough." With the unversioned key, Chromium's cold start does more than a million location lookups on 4 vCPUs, all through that one mutex. Successful hits also hold the lock longer (prefix compare + `shared_ptr` copy) than a versioned miss.
- Each location hit still **materializes** a private copy (`store_block` memmove, icache, link table). Compiling was already cheap (<1%), so avoiding 0.33M compiles does not pay for 0.87M extra materializations plus the convoy. Spawn still won 1.7× because that workload was 545 compiles per `/bin/true`.

Step 2 is a separate cost and is unchanged: every A64 BL carries an extra `direct_link` relocation for the return record, paid at compile and at every materialization. It stays opt-in. c2 does not turn it on.

### The variant (c2)

Shard the location index the same way as the guest-PC directory: 64 padded `shared_mutex`es, keyed by `LocationKey` hash, with the per-shard maps pre-reserved. Kernarium `port/page-key` `3ecd109` (local only, not pushed). Binary `uml-darwin-port-pksh`, md5 **e77bb9bc**, on top of c1 (budget 16384, return stack off). The unversioned key is still opt-in (`UML_JIT_SHARED_LOCATION_UNVERSIONED=1`) in this binary.

Gates: JIT unit tests **61/61** (the same 3 suites still don't build); the unversioned location test in `arm64-jit-shared-translation-chunks` passes.

### Chromium A/B, interleaved, same session (12:17:38–12:28:11 PM ET)

`pksh-gate.sh`, 4 CPU / 4G, budget 4G/128M, five rounds of official / c1+unversioned (unsharded) / pksh+unversioned.

| binary | cold s | mean | med | scroll fps mean | warm s mean |
| --- | --- | ---: | ---: | ---: | ---: |
| official 0022 (n=5) | 6.62 6.75 6.90 6.22 7.36 | **6.77** | 6.75 | 12.1 | 0.68 |
| c1 + unversioned, unsharded (n=5) | 8.55 8.19 8.65 7.26 8.28 | **8.19** | 8.28 | 12.6 | 0.76 |
| **c2 = pksh + unversioned, sharded (n=5)** | 6.37 6.25 5.86 6.05 5.92 | **6.09** | 6.05 | 12.7 | 0.90 |

Unsharded step 1 still costs about **+1.4 s** in this session (reproducing the earlier +0.8 s, here a bit larger). Sharding removes that regression and is **0.68 s faster than official (10%)** on cold start. Every c2 cold is at or under official's median. Scroll is at parity or a little better (12.7 vs 12.1). Warm is a bit slower (0.90 vs 0.68); not enough to cancel the cold win, but real.

### Spawn A/B, same session (12:30:38–12:32:16 PM ET)

ASLR on, 4 CPU / 4G. `sh_true_1000` is the original 1.7× bench (busybox `sh` loop of `/bin/true` ×1000). `sh_c_true_300` is `sh` looping 300 times on a `#!/bin/sh` script that runs `/bin/true` (close to the old script-spawn case). Two VMs each, two of each loop per VM.

| phase | c2 (pksh + unversioned) | official 0022 | ratio |
| --- | --- | --- | ---: |
| sh_true_1000 | 1.84 1.78 1.80 1.80, mean **1.81** | 3.49 3.63 3.48 3.71, mean **3.58** | **2.0×** |
| sh_c_true_300, first in a VM | 1.42 1.41, mean **1.42** | 8.59 8.47, mean **8.53** | **6.0×** |
| sh_c_true_300, second in a VM | 1.39 1.38, mean **1.39** | 18.46 18.49, mean **18.48** | **13×** |

The official second script-spawn in the same VM is consistently ~18.5 s (reproduced in both official VMs): version bumps from the first 300 execs make the next 300 miss even harder. c2 stays flat. The 2.0× on `sh_true_1000` is a little better than step 1's original 1.7× (3.61 → 2.11), likely the 16384 budget on top of the unversioned key.

### Verdict on uml-darwin

**c2 is a clear net win on uml-darwin** against official 0022: Chromium cold **−10%**, spawn **2.0×** (and 6× on the script-spawn case), gcc expected to keep c1's **3.2%** (budget 16384; sharding is off the gcc path). The return stack stays off. Official `uml-darwin` / `uml-darwin-official-0022-20261113` (md5 6ea8180e) and the iOS runtimes are untouched. Kernarium is not pushed. Swap stayed at 512/2048 MiB; no SWAP_ABORT.

c2 is **not** yet a default: the unversioned key is still opt-in in the binary. Landing it means flipping that default on `port/page-key` and gating D4iPad (Firefox + Chromium + footprint), with rollback from `scratch/KRuntime_6_18_4K.xcframework.official0022`.

### Remaining gap vs crate, and switch vs port (David's set: Chromium, terminal, Tailscale, Grok Bot, Grok CLI)

Crate vs official 0022, same mini, 14 Nov 8:30–9:20 AM ET (crate software rendering; Kernarium virgl/GPU). After c2, the leftover is still large, and it is structural.

| workload | crate | official 0022 | c2 (this afternoon) | leftover vs crate |
| --- | ---: | ---: | ---: | --- |
| Chromium cold | 3.82 s (3.46–4.03) | 6.96 s then; 6.77 s today | **6.09 s** | still **~1.6×** |
| Chromium scroll | 54.7 fps (software!) | 11.5 then; 12.1 today | 12.7 fps | still **~4×** |
| Chromium warm | 0.47 s | 0.63 then; 0.68 today | 0.90 s | crate still ahead |
| spawn `sh` ×1000 `/bin/true` | 0.85 s | 3.58 s today | **1.81 s** | still **~2.1×** |
| gcc -O2 | 12.5 s | 57.8 s (c1 A/B) | not re-run; c1 was 56.0 s | still **~4.5×** |
| node int / fp, python | 1.1–1.2 / 0.9–1.1 / 1.2 s | 1.5–1.6 / 1.7 / 2.8 s | unchanged (no identity mapping) | **1.4–2.3×** |
| boot to desktop | 7.4 s (Debian Xfce) | 3.3 s (Alpine labwc) | unchanged | Kernarium still **~2×** faster, different guest |

What crate still does that we do not, with measured attribution:

1. **No per-process materialization (the big remaining spawn / browser-launch lever).** Crate's cache is per-CPU and keyed by physical page; `page_va` plus offset is applied at run time, so a new process installs nothing. After c2 we reuse translations across ASLR/exec, but we still memmove a private copy, rebuild link tables and flush icache for every new address space. Step 0's SIGPROF, once compiles were gone, was memmove 30%, link-table 16%, icache 14%, shared find 8%, translated code only 8%. That is the leftover **2.1× spawn** (1.81 vs 0.85 s) and most of the leftover **1.6× Chromium cold** (6.09 vs 3.82 s). Closing it is crate's "install once" design: a physically keyed, run-time PIC cache. High effort; it changes the link-ownership contract (links are per address space today).
2. **Faster translated code and far fewer dispatcher exits (the gcc / scroll lever).** gcc is not a translation problem (0.02% of the run, 35 G guest instructions). After the return stack (~4%) and the 16384 budget (~3%), gcc is still **~4.5×** behind (56 vs 12.5 s). Chromium *scroll* is still **~4×** behind *even though crate was in software and we have a GPU*. Cheap knobs did not move this: 15-register in-block pinning was a no-op and was dropped; the software return stack is weaker than crate's host BL/RET through the hardware return stack; 29 M dispatcher exits/gcc run remain (indirect misses, chain breaks). Register identity mapping (guest Xn in host Xn) and true host-RET prediction are the intended ports; they are large changes, and they are what should show on tight loops (node 1.4×, python 2.3×) and on V8/Chromium C++ (scroll).
3. **Guarded cross-page chaining** only matters together with (1). Not yet relevant.

**Switch vs port, for this use on iOS:**

- **Port, don't stop.** c2 is a real, shippable uml-darwin win for the terminal (spawn 2×) and a modest Chromium cold win (10%), and it does not require changing products. The next port that can still move Chromium *a lot* is (1), the PIC / no-materialize cache. Until that lands, we will not catch crate on Chromium scroll or gcc. Pretending otherwise would be wrong.
- **Do not switch the iOS product to crate today.** crate's Mac numbers are the more usable Chromium (cold 1.8×, scroll 4–5×, and Grok Bot is Chromium inside, so it gets the same). The Grok Build CLI is a native arm64 binary and the terminal is spawn-heavy, so they would feel it too. Tailscale is a long-running daemon, so it cares more about (2) than about spawn. But those numbers are Mac-only, and crate ran **without a GPU stack** (the published scripts build iOS ANGLE/virgl, not macOS). Kernarium already has a working D4iPad path (virgl / KosmicKrisp, phone JIT 3584M/64M, hybrid 97/93, measured footprints). crate is v0.1.1; its iOS memory budget, input, display, and Tailscale/slirp behaviour on a 12 GB-class device are unproven. Both need a JIT, so neither is an App Store build as-is (V8 still generates code; S2Arm's ahead-of-time trick does not apply). Boot still favours Kernarium's native-kernel UML + slim Alpine. Switching is a product rewrite of packaging, launch, budget and device integration, under crate's MPL-2.0, not a drop-in.
- **A fair switch decision needs a crate-on-iOS spike** (GPU, device memory, Chromium cold/scroll/footprint on the same D4iPad-class setup), in parallel with porting (1). If crate is still 4× on scroll *on the device*, switching becomes the serious option. Until that spike exists, keep porting in Kernarium and treat crate as the measured target, not the shipping runtime.



## c2 iOS gate on D4iPad-on-Mac and Peek Simulator (14 Nov 2026, 12:43–13:40 ET)

c2 is the sharded 64-way location index (`3ecd109`) plus the unversioned location key as the default (`dbbdd7e` on local `port/page-key`; `UML_JIT_SHARED_LOCATION_VERSION=1` restores the versioned key). Return stack stays off. Official `uml-darwin` / `uml-darwin-official-0022-20261113` (md5 **6ea8180e**) and the official 0022 iOS backup were not touched. Kernarium was not pushed.

Phone-default profile throughout: JIT 3584M/64M, guest 3072 MiB, 8 vCPUs, 1920×1080, persist off, one destination at a time, footprint via `footprint-sampler.sh`.

### D4iPad is Designed-for-iPad on the Mac mini, not a physical iPad

A previous pass treated `xcrun devicectl list devices` showing `iPad.coredevice.local` (iPad mini 6th gen, unavailable) as a blocker. That was an agent misread, not a launch-script destination bug. `launch-d4ipad-0022.sh` already uses `-destination "platform=macOS,variant=Designed for iPad"` (My Mac UDID `00006020-0009715A216B401E`), Aqua `gui/501` LaunchAgent, and lldb `jit_serve`. This session confirmed that destination on the live xcodebuild command line. The other iOS target is Peek iPhone 17 Simulator (`8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB`). Nothing was rebooted; no physical iPad was chased.

### Same-session hybrid 97/93 baseline, then c2, on D4iPad-on-Mac

Current shipping default at the start of the gate was hybrid 97/93 (device **20643a83**, Sim **0415aeb3**), already a footprint win over raw official 0022. A restore point was cloned to `scratch/KRuntime_6_18_4K.xcframework.hybrid9793` before packaging c2. If c2 had not landed, that — not official 0022 (`78ac5040` / `97092f94`) — was the rollback.

Baseline of the then-current hybrid, 12:43:46–12:57:35 ET. Wrapper `rc=1` on all four runs is not a guest failure: `run-d4ipad-interactive.sh` ended on `grep SWAP_ABORT | tail` under `pipefail` when there was no abort (xcodebuild `** TEST SUCCEEDED **`, `d4ipad-0022-last-exit.txt` was 0). The wrapper now exits with that last-exit status. `shared_evict` was not in the D4iPad guest-session path this session (reported `na`); Simulator logs below do have it.

First c2 launch attempt at 12:59:42 ET was refused: reclaimable headroom 5759M < need 6144M. `launch-d4ipad-0022.sh` had hardcoded `UML_PREFLIGHT_GUEST_MEM=4G` even for the 3072 MiB phone guest (need = 4G + 2048M margin). After the device cmake build, headroom was just under that conservative bar. Preflight now uses the actual `GUEST_MIB` (need = 3072+2048 = 5120M). The mid-run swap abort (+2048M from start) is unchanged. The two `rc=3` attempts were discarded. Retry started 13:01:11 ET on c2 device runtime **f9dd3963** (`UML_IOS_DEBUGGER_JIT=ON`, `port/page-key` `dbbdd7e`).

| run | cold s | scroll fps (frames, p95 ms) | warm s | peak footprint MB | peak RSS MiB |
| --- | ---: | --- | ---: | ---: | ---: |
| hybrid c2bl-ff-1 12:47 ET | 27.21 | 54.22 (109, 17.40) | 1.99 | 4918 | 4307 |
| hybrid c2bl-ff-2 12:50 ET | 25.93 | 47.90 (96, 33.60) | 2.10 | 4775 | 4204 |
| **c2-ff-1 13:04 ET** | **25.53** | 49.84 (100, 50.00) | 2.00 | **4174** | 4235 |
| **c2-ff-2 13:07 ET** | **25.96** | 54.19 (109, 33.32) | **1.76** | **4213** | 4122 |
| hybrid c2bl-cr-1 12:53 ET | 9.05 | 7.84 (16, 516.60) | 1.00 | 4610 | 4141 |
| hybrid c2bl-cr-2 12:57 ET | 8.25 | 7.75 (16, 599.90) | 0.95 | 4582 | 3918 |
| **c2-cr-1 13:11 ET** | **7.55** | **12.18 (25, 233.40)** | 1.08 | **3829** | 4020 |
| **c2-cr-2 13:14 ET** | **7.36** | **9.96 (20, 333.30)** | 1.02 | **3862** | 4039 |

Last-night refs, same profile, ET: official FF offf-1 24.62 s / 50.90 fps / 2.04 s / 5385 MB; hybrid 97/93 FF 25.32–25.78 s / 52.1–52.8 fps / 1.94–1.97 s / 4754–4776 MB; official CR ~9.26 s / 8.35 fps / 1.01 s / 4639 MB; hybrid CR 9.16–9.40 s / 8.4–10.9 fps / 0.89–0.99 s / 4593–4597 MB.

D4iPad vs this session's hybrid: Firefox cold is parity once the first-after-idle hybrid 27.21 s is set aside (25.53–25.96 vs 25.93; last-night official 24.62 is still ~1 s faster). Firefox scroll and warm are parity. Chromium cold is a clear win (**7.36–7.55 vs 8.25–9.05**, about 16%, and vs official ~9.26). Chromium scroll is a clear win (9.96–12.18 vs 7.75–7.84). Footprint is the large, unambiguous win: Firefox **4174–4213 vs 4775–4918** (about 560–740 MB) and vs official 5385; Chromium **3829–3862 vs 4582–4610** (about 720–780 MB). Chromium first_paint also collapsed (22.6–38.8 ms vs hybrid 572–627 ms). All eight completed runs were `rc=0` after the wrapper fix.

### Peek Simulator

c2 sim slice **4420992a**, packaged with device+sim (MesaEGL/MesaGallium/HostBattery/HostVideoEncoder keep both slices; a D4iPad-only package would have left them device-only, as last night). Destination `platform=iOS Simulator,id=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB`, `-parallel-testing-enabled NO`. Peek was Shutdown during the D4iPad gate and only booted for this block.

No same-session Simulator hybrid baseline (the sim slice was removed by the device-only package, then rebuilt as c2). Comparison is last-night's same-machine, same-profile hybrid 97/93 (01:15–01:29 ET) and official simoff-ff-1.

| run | cold s | scroll fps (frames, p95 ms) | warm s | peak footprint MB | evict | shared ins | peak RSS MiB |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| simoff-ff-1 last night | 28.43 | 51.66 (104, 33.48) | 2.52 | 5013 | 327002 | 1509396 | 4096 |
| simh97-ff-1 last night | 27.74 | 48.31 (98, 50.28) | 2.26 | 4408 | 391125 | 1447092 | 3429 |
| simh97-ff-2 last night | 26.92 | 48.40 (97, 50.20) | 2.28 | 4398 | 321446 | 1441849 | 3617 |
| **c2sim-ff-1 13:20 ET** | 28.16 | 44.02 (95, 49.76) | 2.05 | **3784** | **0** | 809745 | 2554 |
| **c2sim-ff-2 13:23 ET** | 27.84 | 48.78 (98, 50.00) | 2.50 | **3769** | **0** | 805743 | 2766 |
| simh97-cr-1 last night | 9.71 | 14.46 (29, 283.40) | 0.93 | 4208 | 61923 | 1385692 | 3060 |
| simh97-cr-2 last night | 9.63 | 20.74 (42, 183.28) | 0.83 | 4213 | 62451 | 1390509 | 3248 |
| **c2sim-cr-1 13:26 ET** | **8.38** | **26.22 (53, 91.70)** | 1.20 | **3503** | **0** | 933090 | 2752 |
| c2sim-cr-2 13:26 ET | — | stalled: `DESKTOP_FAILED labwc no wayland socket` at 13:27:11, then `sleep 3600`. Aborted at 13:35:04. Peak RSS had been 1259 MiB, then 52 MB. Swap grew 504/2048 → 1873/3072 MiB. Not a timing result. | | 1330 | 0 | 74054 | 1258 |
| **c2sim-cr-2b 13:39 ET** (Peek shutdown/boot retry; leftover swap ~1825/3072) | 11.23 | 18.26 (37, 129.90) | 1.23 | **3501** | **0** | 934590 | 2847 |

Simulator Firefox cold is a slight regression vs last-night hybrid (27.84–28.16 vs 26.92–27.74, about 0.4–0.9 s) and close to official 28.43. Scroll is mixed (ff-1 44.02 vs 48.3; ff-2 48.78, parity). The clear Simulator wins are footprint (**3769–3784 vs 4398–4408**, about 630 MB; vs official 5013) and **shared evictions 0 vs 321k–391k**, with about half the shared insertions. Chromium c2sim-cr-1 is a clean win on cold (**8.38 vs 9.63–9.71**), scroll (**26.22 vs 14.46–20.74**), and footprint (**3503 vs 4208–4213**), also evict 0 (vs 62k). c2sim-cr-2b completed with the same footprint and evict 0, but a slower 11.23 s cold after the stall and a Peek restart under leftover swap; treat cr-1 as the primary Chromium Simulator sample. Peek was shut down after the retry. The mini itself was not rebooted.

### Verdict and landing

**c2 is a clear net win as the iOS default** against the then-shipping hybrid 97/93, with official 0022 cited as the older baseline.

- Chromium cold and scroll improved on D4iPad-on-Mac and on the clean Simulator run.
- Firefox cold/scroll are parity on D4iPad and only slightly slower on the Simulator; not enough to cancel the rest.
- Footprint is substantially better on both destinations and both browsers (about 560–780 MB).
- Simulator evictions went to zero, which is the c2 mechanism showing up: the sharded unversioned location index no longer chews the shared cache the way hybrid 97/93 did (320k–390k Firefox evictions last night).

Landed in `Kernarium-0022-clean` `.build/kernarium-xcframeworks` (device **f9dd3963**, sim **4420992a**), with a snapshot at `scratch/KRuntime_6_18_4K.xcframework.c2-dbbdd7e`. Rollback is still `scratch/KRuntime_6_18_4K.xcframework.hybrid9793`. Official 0022 backup and official `uml-darwin` (6ea8180e) are intact. The separate `src/Kernarium` worktree xcframework was not overwritten. macOS `uml-darwin-port-pksh` (e77bb9bc) is still the pre-`dbbdd7e` binary (unversioned key opt-in there); iOS builds from `dbbdd7e` have the default flip.

### Next performance work (not this gate)

Kernarium's goal is max-performance full Linux. Chromium is one benchmark among general workloads. The leftover vs crate is still the one written this afternoon: (1) no-materialize / install-once PIC cache, (2) fewer dispatcher exits and faster translated code (register identity, host BL/RET). Those are the next levers. A Chromium-kiosk product mode was considered and dropped.



## Install-once PIC translation cache: design for the next lever (14 Nov 2026, 1:42–1:50 PM ET)

c2 is landed as the iOS default (NOTES `d7c8723`). The leftover vs crate is still structural: after the unversioned, sharded location index, a new process still **materializes** a private copy of every reused translation. SIGPROF on the static-parent `/bin/true` path (compiles already gone) was memmove **30%**, link-table create/find **16%**, `sys_icache_invalidate` **14%**, shared find **8%**, translated guest code only **8%**. That is the leftover ~2.1× spawn (c2 1.81 s vs crate 0.85 s) and most of the leftover ~1.6× Chromium cold (c2 6.09 s vs crate 3.82 s). gcc and scroll stay a later lever (dispatcher exits / faster translated code).

This chunk is design and path inventory only. No Kernarium code change, no uml-darwin or iOS rebuild (the mini Data volume is at 96% with 19 GiB free; another worker is freeing space). Session `/tmp` diags from the c2 Simulator stall were deleted. Official `uml-darwin` (6ea8180e) and the three KRuntime snapshots (`official0022`, `hybrid9793`, `c2-dbbdd7e`) were left alone. Kernarium was not pushed.

### How materialization works today (`port/page-key` `dbbdd7e`)

`JitExecutor::install_shared_translation` in `jit_executor_cache.cpp`:

1. Find the shared template by backing-page location (c2's unversioned, sharded index).
2. `slid_relocations()` adds the ASLR slide to every `guest_pc` and to every direct/indirect link key.
3. `materialize_shared_translation()` pre-allocates this address space's indirect-link slots.
4. `ExecutableArena::store_block()` **memcpy**s the whole template into the private L1 executable arena, `find_or_create`s a `JitBlockLink` for this block and every direct-link target, patches the in-block 64-bit literal-pool slots with those pointers and the slid guest PCs, then **`invalidate_instruction_cache`** on the copy.
5. `store_native()` installs the private copy in this executor's L1.

`JitRelocationKind` is only three cases, all recorded by `Arm64Emitter::load_relocatable_pointer` as `LDR` (literal) into a tail pool (or a nearby island if imm19 cannot reach), then rewritten in `store_block`:

- `guest_pc`: a guest virtual address (store_pc, BL return).
- `direct_link`: a pointer to this address space's `JitBlockLink` for the target key.
- `indirect_link`: a pointer to this executor's indirect site.

The shared payload (`translation->words`) is an ordinary heap allocation, not executable. Links are per address space because they carry `activation_epoch` and point at that space's records. That is why a new process pays memcpy + relink + icache even when c2 finds every block.

### PIC v1 (this lever's first measurable slice): execute the template once, per-AS GOT

crate's end state is a physically keyed, per-CPU RX cache with `page_va+offset` applied at run time and guarded cross-page chaining, so a new process installs nothing. Porting that in one step would change the link-ownership contract and the compiler together. v1 keeps today's per-AS `JitBlockLink` table but **stops copying and flushing code**.

- At **publish** (once per unique block, not per process): write the template into a process-wide shared **RX** arena. The executable bytes never contain address-space-specific values.
- Relocatable `LDR` (literal)s become **GOT loads** (`LDR Xt, [xGOT, #imm]`) from a compact per-AS table, one 8-byte slot per relocation. Filling the GOT is a small data write; it does not need an icache flush of the translation.
- A64 first (Alpine userland, Chromium, Firefox, gcc, spawn are A64). AArch32 keeps today's `store_block` path: the extended frame already uses x22–x28 for guest registers.
- `xGOT` is a callee-saved register reserved for A64 PIC chains and saved/restored in the prologue, or a new `JitChainState` pointer loaded from x19. x19 is already the chain-state pointer, x20 the budget, x21 the link selector; those stay. AArch32 is unchanged, so the reserved register must not collide with the extended frame. Preferred: add `void *reloc_got` to `JitChainState` (72 → 80 bytes) and load from `[x19, #offset]` so A64 does not steal x22 from a future register-identity port. A two-load GOT hit (state then slot) is acceptable for v1; a reserved register can come later if the load shows up in SIGPROF.
- `install_shared_translation` on an A64 PIC template: build the GOT, create the same link records as today, point L1 at the **shared RX entry** plus this GOT, and skip `store_block`'s memcpy and icache flush. Failure falls back to a local compile, as today.
- Opt-in first: `UML_JIT_SHARED_PIC=1`. Do not flip a default until uml-darwin spawn/gcc/node/python plus Chromium/Firefox are a clear win against c2 and official 0022, and then a D4iPad-on-Mac + Peek footprint gate.

Expected from the existing profile: drop the 30% memmove and 14% icache from the no-compile spawn path; the 16% link-table work remains until v2. That should move spawn and Chromium cold, and should leave gcc/scroll flat (they are not translation-bound).

### PIC v2 (after v1 is measured)

- `guest_pc` slots computed as `page_va + offset` at run time (true crate-style), so the GOT no longer stores slid guest PCs.
- Guarded cross-page chaining, so following a link does not require a per-AS `JitBlockLink` install on every block just in case. That is the rest of "a new process installs nothing."
- Then the separate leftover: fewer dispatcher exits and faster translated code (host BL/RET, register identity).

### Measurement plan (next chunk, uml-darwin first)

Reuse `scratch/jitprof/{pksh-spawn,k-cpu,pksh-gate}.sh`. Same 4 CPU / 4G, budget 4G/128M, preflight and +2048M swap abort, one VM at a time. Compare:

- official 0022 (`uml-darwin-official-0022-20261113`, md5 6ea8180e), never overwritten;
- c2 (`uml-darwin-port-pksh` is currently pre-`dbbdd7e` and still has the unversioned key opt-in — either rebuild a `uml-darwin-port-c2` from `dbbdd7e` or run pksh with `UML_JIT_SHARED_LOCATION_UNVERSIONED=1`; do not overwrite official or pksh until the new binary is copied aside);
- PIC v1 behind the flag, same c2 baseline otherwise.

Workloads: spawn (`sh` ×1000 `/bin/true`, script-spawn), gcc -O2, shell scripts, node int/fp, python loops, then Chromium and Firefox cold/scroll/warm. Land on uml-darwin only on a clear net win. Only then build an iOS runtime and gate D4iPad-on-Mac + Peek with footprint, vs landed c2 (f9dd3963 / 4420992a) and official 0022. No iOS package in this chunk, to avoid filling the disk.



## PIC v1 implemented, opt-in, unit tests pass (14 Nov 2026, 1:50–2:05 PM ET)

Design (`ae05213`) is now in `Kernarium-0022-clean` `port/page-key` (still unpushed, on top of `dbbdd7e`). Official `uml-darwin` remains **6ea8180e**. The new binary was copied aside as `uml-darwin-port-pic` (md5 **3c52bd13587e0f49b4a40635cf33fb61**, 14:04 ET after the single-instruction fix). Existing `uml-darwin-port-pksh` was not overwritten. No iOS package. Kernarium was not pushed.

### What landed in the tree (opt-in `UML_JIT_SHARED_PIC=1`, A64 only)

- `JitChainState.reloc_got` at offset 72; struct is 80 bytes. AArch32 extended frame and x22–x28 are unchanged.
- `Arm64Emitter::load_relocatable_pointer` in PIC mode emits `LDR` of the GOT pointer from `[x19, #72]`, then `LDR` of the slot. `JitRelocation::word` is a dense GOT index, not a literal-pool word.
- `JitCompiler::set_shared_pic` is set from the env var at executor construction. AArch32 keys stay on today's `store_block` path. Single-instruction fallbacks also force PIC off: they are stored unpatched into a private arena and invoked with a chain that has no GOT.
- Publish records `SharedTranslation.pic` and stores a process-wide RX copy (`store_shared_executable`, 512 MiB bump arena). Shape/insert accept dense GOT slots instead of zeroed in-block literal cells. `make_packed` does not zero PIC slots (that would have clobbered instructions).
- `install_pic_block` creates the same per-AS link records, fills a non-moving private GOT slab, points L1 at the shared (or private unpatched) prologue, and uses a 10-instruction trampoline as `internal_entry` when the block has relocations (`MOVZ/MOVK` GOT, `STR [x19, #72]`, `BR` to the shared internal entry). Zero-reloc blocks jump to the shared internal entry directly. PIC templates never go through `store_block`.
- `execute_native` publishes `block->reloc_got` into the chain before the first prologue.

### Unit tests (macos-unit, 61 suites that already build)

The three suites that still do not compile are unchanged and pre-existing: `arm64-jit-shared-translation-cache`, `arm64-jit-persistent-translation-cache`, `arm64-jit-cache_validation` (they treat packed `span` fields as `vector`). Excluding those:

- Flag off (c2 default in this binary): **61/61 passed** (14:00 ET, 192 s).
- `UML_JIT_SHARED_PIC=1`, first run: 58/61. Three A64 runtime suites segfaulted in `run_single_instruction` (`fp-link-runtime`, `reservation_alias`, `executor-paths`) — PIC-compiled singles loaded `[x19, #72]` then dereferenced a null GOT (`SIGSEGV` at address 0x8). Fixed by compiling singles with PIC off and restoring the flag afterwards.
- `UML_JIT_SHARED_PIC=1`, after the fix: **61/61 passed** (14:05 ET, 136 s).

Default (flag off) behavior is the landed c2 path. PIC stays opt-in until uml-darwin measurement vs official 0022 and a fair c2 baseline (same `uml-darwin-port-pic` binary with the flag off).



## PIC v1 uml-darwin measurement: not a win, keep opt-in (14 Nov 2026, 2:06–2:15 PM ET)

Unit tests were already recorded in `50a7b92`. This chunk ran the first uml-darwin A/B and stopped short of iOS.

Copied binary: `Kernarium-0022-clean/.build/presets/macos-integration/bin/uml-darwin-port-pic` (md5 **3c52bd13587e0f49b4a40635cf33fb61**). Official `uml-darwin-official-0022-20261113` remains **6ea8180e**. Fair c2 baseline is the same `port-pic` binary with the flag off (tree is `dbbdd7e` plus the PIC opt-in; unversioned location key is already the default). Kernarium was committed locally only on `port/page-key` (PIC JIT sources); it was not pushed. Pre-existing dirty non-JIT files were left unstaged.

### Spawn (4 CPU / 4G, budget 4G/128M, preflight +2048M swap abort, slim Alpine, 14:06 ET)

Swap used was still 1761/3072 MiB; headroom 6430–7044M vs need 6144M; preflight allowed the runs. No SWAP_ABORT.

| tag | binary | sh_true_1000 a/b | sh_c_true_300 a/b |
|---|---|---|---|
| **sp-picbin-c2-1** 14:06 ET | port-pic, flag off (c2) | **2.03 / 2.00** | **1.61 / 1.58** |
| **sp-picbin-pic-1** 14:06 ET | port-pic, `UML_JIT_SHARED_PIC=1` | — | guest panicked at 0.41 s |
| **sp-picbin-off-1** 14:06 ET | official 0022 (6ea8180e) | **3.64 / 3.74** | **8.80 / 19.20** |

c2 vs official is the same picture as this afternoon: spawn about 1.8×, script-spawn much faster, official's second script-spawn in the same VM still blows up (~19 s, previously ~18.48). PIC on never reached the spawn payload.

PIC boot log: `mount[103]: segfault at d3cc07580 ip 0000000d3cc07580 sp 00007fffc52b7d10 error 10`, then `UML_BOOT_ERROR:cannot mount devtmpfs`, `Kernel panic - not syncing: Attempted to kill init!`. `/init` started; the first `mount` (devtmpfs) died. The fault address looks like a host heap pointer used as a branch target (UML reports it as a guest SIGSEGV). Unit tests, including the A64 runtime suites, did not catch this; they do not fork a second guest address space that reuses a published PIC template the way `init` then `mount` does. Trampoline MOVZ/MOVK/STR/BR encodings were disassembled and are correct in isolation.

No gcc/node/python or Chromium/Firefox numbers for PIC (the VM cannot boot). Those were not rerun for c2/official in this chunk; prior c2 vs official figures still stand. Did **not** package an iOS runtime or start a D4iPad-on-Mac / Peek gate.

### Verdict

**Not a clear win. Keep `UML_JIT_SHARED_PIC=1` opt-in. Do not land as the iOS default.** Flag-off remains landed c2. Next work is to fix the multi-AS reuse crash (mount at early boot) before measuring again.

Note: mid-measurement, `scratch/jitprof/` disappeared (another worker is freeing disk). Official and `port-pic` binaries, preflight, `notes/cpu-benches`, the slim rootfs, and the KRuntime snapshots were still present when this was written. Recreate a small spawn/cpu harness from the scripts already recorded in NOTES if that directory stays gone.

