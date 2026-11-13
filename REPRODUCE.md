# Reproducing the Kernarium Simulator bakeoff

Host: Apple Silicon Mac, Xcode 26.6, iOS 26.5 Simulator. Nothing in this doc installs on a physical iPhone.

Upstream: `imxieyi/Kernarium` at `ce0fa868`. Apply `patches/0001-simulator-26.5-local-artifacts-and-uml-window.patch` on top. That patch:

- Lowers deployment targets and GuestHostCore to iOS 26.5
- Adds AVAudio / BackgroundTasks / PiP fallbacks for the 26.5 SDK
- Drops `KRuntime_Android_6_18_4K` from Embed Frameworks and points Ghostty at a local package
- Host-page-aligns the UML native kernel window (required on the 16 KiB Simulator)
- Pins home-built kernel and boot-base release ids / SHA-256s (replace with yours if you rebuild)

Do not commit the 73 MiB Ghostty xcframework, kernel images, or rootfs images to git. Large artifacts belong in Google Drive (`gdrive:linux-ios-fast/` if uploaded from this bakeoff).

## 1. Case-sensitive volume

The kernel tree needs a case-sensitive APFS volume:

```sh
hdiutil create -size 50g -fs 'Case-sensitive APFS' -volname KernariumCS -type SPARSE \
  ~/linux-ios-bakeoff/KernariumCS.sparseimage
hdiutil attach ~/linux-ios-bakeoff/KernariumCS.sparseimage
```

There is no LaunchAgent for this image. After a macOS reboot, attach it again with the same `hdiutil attach` command before using `/Volumes/KernariumCS`.


## 2. Arm64 Linux with sudo (Lima)

The box and Hetzner box used here are x86_64; do not use them for these builds. On the Mac:

```sh
limactl start --name kernarium-linux --vm-type vz --arch aarch64 --cpus 4 --memory 8 --disk 25
# Then follow Kernarium's starter/build-all.sh and kernel build docs inside the VM
# and on the case-sensitive volume.
```

After the kernel is built, copy the artifact as a *real directory* (not a symlink) to:

`Kernarium/.build/kernel/artifacts/mainline-6.18-arm64-4k-<release>/`

Update `kernel/mainline-6.18/artifacts/accepted-4k.env` to match the release id, directory, and `6.18.60-g<hash>`. Keep a `accepted-4k.env.upstream` backup.

Boot-base: put `uml-boot-base-aarch64.cpio.gz` under `.build/rootfs/<RELEASE>/` and pin it in `tools/rootfs/boot-ramdisk/accepted-aarch64.env`. Strings in that file must be single-quoted; `UML_BOOT_BASE_SIZE` is unquoted.

Alpine: build a small aarch64 3.24.2 GPT image, extract the ext4 partition, and (via Lima, not virtiofs) install `scripts/guest-run-benches.sh` as `/usr/local/bin/run-benches.sh`. Example inittab:

```
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::once:/usr/local/bin/run-benches.sh
::shutdown:/sbin/openrc shutdown
```

`scripts/patch-alpine-benches.sh` does the copy / e2fsck / loop-mount / copy-back dance. After copy-back, `chmod u+w` the macOS-side ext4 (it can come back mode 444).

## 3. GPU / Mesa (Simulator)

`dependencies/build-apple-gpu.sh` must put GNU bison ahead of Mesa's sanitized PATH (included in the patch). LLVM may take around 10 minutes. The script can leave a multi-gigabyte work tree; delete it when the prefix is published to `.build/dependencies/apple-gpu-vulkan-experiment/ios-simulator-arm64/`.

## 4. Ghostty

Remote SPM resolution of `libghostty-spm` 1.6.20260922 can hang on the 73.4 MiB zip. Prefetch and vendor:

```sh
scripts/vendor-libghostty.sh ~/linux-ios-bakeoff
# checksum 804d4c92cad153eb8d85ed86f4c98ca587e90ff47ac0a62c846c985ece02a9c3
```

Use `Package.local.swift` in `vendor/libghostty-spm` and the pbxproj XCLocal package path from the patch.

## 5. Build the Simulator app

```sh
cd /path/to/Kernarium
cmake --build --preset kernarium-ios-simulator
# Package only KRuntime_6_18_4K + MesaEGL + MesaGallium for the Simulator;
# reuse existing GPTFDisk and LibZstd xcframeworks. Official
# package-ios-frameworks.sh --sdk simulator also wants the Android runtime
# and is heavier than this app needs.
# Then:
UDID=8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB
xcodebuild build \
  -project Kernarium/Kernarium.xcodeproj \
  -scheme Kernarium \
  -destination "id=$UDID" \
  -derivedDataPath .build/kernarium-simulator-derived \
  -jobs 8 \
  CODE_SIGNING_ALLOWED=NO \
  EXCLUDED_ARCHS=x86_64
```

The reproducible Simulator rebuild is `scripts/build-kernarium-simulator.sh /path/to/Kernarium`. It copies the iOS-applicable JIT series (`patches/0013-jit-publish-arena/`, evict + packed publish + bump arena), the Simulator `vm_region_64` fix (`patches/0014-simulator-vm-region-64/`), and the optional JIT cache-budget override (`patches/0015-kernarium-jit-cache-budget`) into the checkout, runs only `cmake --build --preset kernarium-ios-simulator`, packages `KRuntime_6_18_4K.xcframework`, and `xcodebuild`s a `Release-iphonesimulator` `Kernarium.app`. It does not build the `macos-integration` preset, does not touch the official `uml-darwin` identity, and does not install on a physical iPhone. `SKIP_PATCH=1` uses the checkout sources as they already stand. MesaEGL/MesaGallium xcframeworks are reused if they are already in `.build/kernarium-xcframeworks`. Pass a budget into the Simulator with `SIMCTL_CHILD_KERNARIUM_JIT_CACHE_BUDGET` (K/M/G); `SIMCTL_CHILD_UML_JIT_SHARED_STATS=1` dumps `===JIT_SHARED_STATS===`. The default remains 1 GiB. A 4 GiB budget funds a real shared tier but filled before Firefox Web Content started on this host and drove ~7.3 GiB of swap on the 16 GiB mini — do not raise it further here, and unset the `SIMCTL_CHILD_*` variable after a 4G run because it persists in the shell.

`scripts/rebuild-and-relaunch.sh` is an older wrapper that also installs onto Peek and launches. Symlink the ext4 into the app Documents container as shown in NOTES.md. Delete `tmp/kernarium-overlay.ext4` after changing the base image.

If you see `UML: cannot reserve a ... native kernel window` and guest status -4, the window alignment patch is missing or the reservation is not 16 KiB aligned.

## 6. Benches

`scripts/capture-benches.sh` launches with `--console-pty` and waits for `===BENCH_DONE===`. The guest script prints the same suite used for LinuxRunner: `sh` loop 20k, `dd` 32 MiB, `sha256sum`, `apk add tree`, `apk add openssl`, `openssl speed -seconds 3 -evp sha256 aes-256-cbc`.

Typing into `simctl launch --console-pty` did not reliably reach the ttyS0 shell (the PTY echoes but the guest did not execute typed commands). Boot-time script output on the console is the reliable path.

## Phone

Do not install on a physical iPhone until David agrees and a device build has been tested. Device work still needs signing, official iphoneos packaging (KosmicKrisp / Metal 4), and a check that the UML window reserve works on device. Simulator numbers are not device numbers.

## Large artifacts (Google Drive)

Uploaded 6:39 PM ET Nov 12, 2026 to `gdrive:linux-ios-fast/artifacts/` (rclone on the box; verified with `rclone check`, 0 differences), then updated 9:19 PM ET with the Mesa+Falkon desktop image and the munmap-fix kernel:

| File | SHA-256 |
| --- | --- |
| alpine-3.24.2-minimal.ext4.gz (8.0 MiB; uncompresses to the 115,687,424-byte slim-init ext4) | `2a5e3b79bab10d07a732e22e09a247702b28ce4a66e617185e21953a0f0d5e2d` |
| alpine-3.24.2-desktop.ext4.gz (991,029,687 bytes / 945 MiB; uncompresses to a 4 GiB XFCE+virgl Mesa ext4, sha256 `c7f65c84613ca27f22a634779ecc3b6ae7fac68ff5e367530280e7fac74e73ad`) | `0ecc51926f03b0ae5b0a1ff5fcd339b08d98e9a0a5cc21dfa7117a85b9a18599` |
| alpine-3.24.2-desktop-fast.ext4.gz (1,091,530,692 bytes; **journal-replayed clean**, same Drive file ID as the previously shared link; uncompressed sha256 `caa0801f2b19c5868afc9cd345b34a6ec0188b69b722d9262f1081923551fd1a`) | `e4a1f6858ec238ca313e5abef2de6897e018ae675950e115dff4acbb0b9c1d6b` |
| alpine-3.24.2-desktop-fast-dirty-journal.ext4.gz (994,836,889 bytes; previous dirty snapshot, kept) | `721b2c12359178511e9741846385155c9f2847d86c978bae1a6bf30c02c6f6d8` |
| alpine-3.24.2-desktop-labwc.ext4.gz (1,091,534,974 bytes; **journal-replayed clean**, same Drive file ID as the previously shared link; uncompressed sha256 `02a13eb21a63956f625f1f1789ae979ba0c4fbf2c0010f429ed4c867fe8b0617`) | `2a219e5409a7e3a52a197a624d6edd5862270edd95014bc57d241347d208a7eb` |
| alpine-3.24.2-desktop-labwc-dirty-journal.ext4.gz (994,819,499 bytes; previous dirty snapshot, kept; uncompressed sha256 `0564698ccf4064b975e7998a471295d279d9b3542f2b95802c54aad41e5fdab3`) | `9471344de45d308d2f4bb4db20b076be906d431ba935f15f2d56e00d21901480` |
| kernel-mainline-6.18-arm64-4k-20261112-6.18.60-local1.tar.gz | `8ee291d44eb085466385b1f3e99bb79ab9c78a6a76378d97d27fa40712e117e2` |
| kernel-mainline-6.18-arm64-4k-20261112-6.18.60-local2.tar.gz | `dc0431b2b5fda6d0cc79cad88b0b5f0dd24a3aaf04da09b66dbd8db473c72bbb` |
| uml-boot-base-aarch64.cpio.gz (1,398,356 bytes) | `4160fae8bd7f98517767c35d6bbaa3818e6711bd96cf9e8c6b387e2a21e5360b` |
| release-manifest.json | `7f5b687f2779047eb067ac4cb83e71685b40ca075f1181505765ea0f4a8b5f55` |

The boot-base SHA-256 is of the cpio.gz itself (same as `accepted-aarch64.env`). A `SHA256SUMS` file sits next to these objects in Drive. The previous desktop image gz (`a00d0372…`, uncompressed `899fe353…`) is stale: it predates the virgl-capable Mesa, Falkon, and session-script updates. Keep `alpine-3.24.2-desktop.ext4.gz` (`0ecc5192…`); `alpine-3.24.2-desktop-fast.ext4.gz` is an additional image with the 13 Nov 2026 fast session scripts baked in (DESKTOP_READY ~8.7 s). `alpine-3.24.2-desktop-labwc.ext4.gz` is a further image with labwc as the default session (DESKTOP_READY ~2.5 s); XFCE remains at `start-desktop-xfce.sh` / `UML_DESKTOP=xfce`. The 13 Nov 02:41 AM ET Drive labwc (and desktop-fast) images were snapshotted with a dirty ext4 journal (`INCOMPAT_RECOVER`). The production overlay mounts them read-only as `/lower`, which cannot replay the journal and panics (`UML_BOOT_ERROR:cannot mount /dev/ubda`). This is not just a 0444 file mode. At 4:32–4:35 AM ET on 13 Nov the original Drive file IDs were updated in place with journal-replayed clean gzs, so already-shared links now serve the clean images; the dirty snapshots were kept as `*-dirty-journal.ext4.gz`. `scripts/macos-metal/pack-rootfs-gz.sh` checks `INCOMPAT_RECOVER` and runs e2fsck (host or Lima) before gzip; `scripts/desktop-guest/install-fast-desktop.sh` no longer uses `poweroff -f`. `scripts/macos-metal/launch-uml-darwin-desktop.sh` refuses a dirty-journal rootfs, copies a clean read-only image to a writable `*.rw.ext4` sibling (APFS clone when possible), and if port 5900 is already taken (macOS Screen Sharing) falls back to `--gpu-vnc-port=5901`.

## Kernel local2 (native-window end alignment)

Apply `patches/0003-um-darwin-align-native-window-end-to-the-host-page.patch` on the Darwin UML 6.18 tree after the existing series (it is also exported in Kernarium as `kernel/mainline-6.18/patches/series/um-darwin-align-native-window-end-to-the-host-page.patch`). Rebuild with `kernel/mainline-6.18/build/build-kernel.sh --slice arm64`, publish as `20261112-6.18.60-local2`, and point `kernel/mainline-6.18/artifacts/accepted-4k.env` at that artifact (a copy is `patches/accepted-4k.env.local2`):

- release `6.18.60-g8246678b2d74`
- final tree `9ae1a0b0ef88af94c633b1971bc15cf6083a3d73`
- ABI version 26, fingerprint `0x1d7ce579d497fc37`

Use Homebrew LLVM 23.1.5 + lld (`clang` and `ld.lld` on PATH; do not set `UML_KERNEL_LLVM=1` unless that is how the previous accepted kernel was built). After install, the boot log must contain `Darwin native window 0xd3fff4000-0xf80000000 (host-page aligned)` (the start address depends on the reservation; the end must be 16 KiB aligned and must match the host window).

## Desktop image (Alpine XFCE, virgl Mesa)

## Simulator JIT (local fork)

Upstream leaves the Simulator on the gadget interpreter so it resembles a
device with no debugger. This fork measures the ARM64 JIT in the Simulator:

- `darwin/cpu/jit_memory/executable_memory.cpp` publishes via MAP_JIT and
  resolves `pthread_jit_write_protect_np` with `dlsym` (the iOS Simulator SDK
  marks the header unavailable; the symbol exists in the process).
- `ContentView.swift` sets `use_jit = 1`. The runtime logs
  `Kernarium: execution engine jit (cache budget …)` when prepare succeeds.
- `KERNARIUM_EXECUTION_ENGINE=jit` can also be passed through
  `SIMCTL_CHILD_KERNARIUM_EXECUTION_ENGINE` as a belt and suspenders.
- Build with `RUNTIME_EXCEPTION_ALLOW_JIT=YES`. The entitlements file includes
  `com.apple.security.cs.allow-jit`.

This is not how a physical iPhone runs without StikDebug. Do not treat these
JIT numbers as a device promise.

## Slim init

To cut OpenRC (~5 s, or ~10 s under a cold JIT) down to about 1 s guest
uptime, inittab is only:

```
::sysinit:/bin/mount -a
::once:/usr/local/bin/run-benches.sh
::shutdown:/bin/umount -a -r
```

`scripts/guest-run-benches.sh` brings up `lo`/`eth0` and runs `udhcpc` if there
is no default route. The hostname stays `(none)` because the OpenRC hostname
service is skipped. `scripts/patch-alpine-benches.sh` plus a rewritten inittab
is how the image is updated (copy off virtiofs onto Lima's disk, e2fsck,
loop-mount, copy back, `chmod u+w`).

The official KDE erofs is unpublished. The desktop guest is a 4 GiB Alpine 3.24.2
ext4 grown from the slim-init image in Lima (copy off virtiofs, `resize2fs`,
`apk add` XFCE / Xorg / Firefox, copy back, `chmod u+w`). The stock Alpine
`mesa-dri-gallium` 26.1.6 package lacks the virgl driver, so Mesa 26.1.6 was
rebuilt in the musl chroot from `https://archive.mesa3d.org/mesa-26.1.6.tar.xz`
with `-Dgallium-drivers=virgl,zink,llvmpipe,softpipe -Dvulkan-drivers=virtio,swrast`
and installed over it. Also installed: Falkon, xdotool, vulkan-tools, fontconfig;
xfwm compositing off; `desktop-ready.sh` drops the 2 s sleep and launches
Firefox (then Falkon) against example.com.

Guest scripts live in `scripts/desktop-guest/` (`start-desktop.sh`, `desktop-ready.sh`,
`bwrap-passthrough.sh`, `inittab`, `fstab` with `devpts`). `start-desktop.sh` starts XFCE
sessionless with `xfwm4 --compositor=off --vblank=off`, installs a bwrap passthrough so
glycin is not stuck on a hung `bwrap --unshare-all` in UML, and hides glycin-loaders only
until the window manager is up (then restores them). That cut XFCE `DESKTOP_READY` from ~26.8 s
to ~8.7 s on the Metal/Zink path and ~7.4 s on llvmpipe. The default launch is now labwc (`start-desktop-labwc.sh`, ~2.5 s READY) because the remaining XFCE cost is ~5.9 s of xfwm4/GTK/Mesa JIT; `UML_DESKTOP=xfce` keeps the XFCE path. labwc and windowed Firefox both composite on guest GLES/EGL `virtio_gpu` / `virgl (zink Vulkan 1.4(Apple M2 Pro (MESA_KOSMICKRISP)))` — real Metal, not pixman or llvmpipe. Firefox 151 still takes ~12 s after READY to paint example.com; that is libxul JIT plus a content process (a local `file://` page is on the same clock; DNS/wget are under a second). The labwc start script now uses a pre-created profile that skips the first-run and telemetry pages. No new Drive image (time-to-page was not cut by 2×). The previous startxfce4 path is
kept only as `notes` history on the bakeoff mini, not in this tree. Do not force `MESA_LOADER_DRIVER_OVERRIDE=virtio_gpu`.
Keep `LIBGL_ALWAYS_SOFTWARE=0` in the guest. The Simulator host still sets
`LIBGL_ALWAYS_SOFTWARE` for its own software Virgl provider.

Launch on an iPad Simulator (larger view than the iPhone 17), after symlinking
the ext4 into the app Documents container and deleting `tmp/kernarium-overlay.ext4`. Use `alpine-3.24.2-desktop-labwc.ext4` for the baked ~2.5 s labwc session, `alpine-3.24.2-desktop-fast.ext4` for sessionless XFCE (~8.7 s), or overlay `scripts/desktop-guest/start-desktop-labwc.sh` (or `start-desktop.sh` for XFCE) onto the previous image:

```sh
UDID=6532E3AA-A7DF-48F4-9E87-6C4EA94F4C74   # iPad (A16)
export SIMCTL_CHILD_KERNARIUM_ROOTFS=alpine-3.24.2-desktop-labwc.ext4
export SIMCTL_CHILD_KERNARIUM_EXECUTION_ENGINE=jit
export SIMCTL_CHILD_KERNARIUM_DISPLAY_WIDTH=1920
export SIMCTL_CHILD_KERNARIUM_DISPLAY_HEIGHT=1080
xcrun simctl launch --stdout=kernarium-desktop.log --stderr=kernarium-desktop.log \
  "$UDID" com.imxieyi.Kernarium
```

The Simulator has no real Metal. labwc's default GLES/EGL virtio_gpu scanout
reaches `DESKTOP_READY` there but never presents a CPU framebuffer, so
`simctl io screenshot` stays black. `scripts/desktop-guest/start-desktop-labwc.sh`
detects the software Virgl provider via guest EDID (`[drm] features: +virgl +edid`
on the Simulator, `-edid` on the macOS Metal path) and sets `WLR_RENDERER=pixman`
only in that case, so labwc scanouts a dumb buffer (the same present path XFCE
already used). Firefox is launched with `MOZ_ACCELERATED=0 MOZ_WEBRENDER=0` on
that path only. Leave `WLR_RENDERER` unset on Metal; callers can still export
it to force a choice. On that same pixman path the script also installs
Simulator-only Firefox prefs after `firefox-kernarium-profile.sh`: software
WebRender, `fission.autostart=false`, and `dom.ipc.processCount=1`. Write
`layers` to `/usr/local/etc/firefox-gfx` to try basic layers instead;
`/usr/local/etc/desktop-browser` with `falkon` launches Falkon (it started
but never painted in 120 s on this path). Leave the content sandbox on.
`firefox-startup-probe.sh` prints spawn/CPU samples to ttyS0 every 2 s.

The Simulator-only sibling `alpine-3.24.2-desktop-labwc-sim-pixman.ext4`
also has that profile script, the probe, and a cheap CJK font
(`font-wqy-zenhei`, ~16.7 MiB installed). The production 0444 / Drive labwc
image is unchanged; the local sim image was updated, but Drive was not,
because Firefox chrome/full-page times stayed about 35 s / 80 s after
`DESKTOP_READY`. See NOTES.md for the before/after table.

Look for `software_display WLR_RENDERER=pixman`, `Kernarium: fixed guest display 1920x1080`,
`execution engine jit`, `===DESKTOP_START===`, `===DESKTOP_READY===`,
`profile_ready`, and `software_firefox_prefs`.
The overlay is disposable; delete it after changing the base image.

`patches/0002-kernarium-display-size-env.md` documents the ContentView change
for the fixed display size.

## macOS Metal (uml-darwin + KosmicKrisp)

The bakeoff mini is on macOS Tahoe 26.7.3 (25G342) as of 13 Nov 2026, 6:37 AM ET (upgraded from 26.3.1 / 25D2128; 27.x was not installed). Xcode 26.6 now lists `My Mac` as `platform=macOS,variant=Designed for [iPad,iPhone]`. `cmake --preset kernarium-ios-device -DUML_IOS_DEBUGGER_JIT=OFF` plus the Linux-only packager `~/linux-ios-bakeoff/notes/package-ios-linux-device.sh` and an unsigned `xcodebuild` Release build for that destination succeed. Launching still needs a development signature for `com.imxieyi.Kernarium` (wildcard team profiles lack the kernel entitlements and this Mac). Do not install on a paired phone. Until signing is fixed, use the official macOS CLI:


```sh
# In the Kernarium tree, after the macos Apple GPU prefix and
# dependencies/prepare.sh --product macos && dependencies/build.sh:
cmake --preset macos-integration \
  -DUML_BUILD_INTEGRATION_TESTS=OFF \
  -DUML_INTEGRATION_ROOTFS= \
  -DUML_MAINLINE_618_KERNEL_ARTIFACT_DIR="$ARTIFACT"
# then build uml-darwin and stage KosmicKrisp / MesaEGL / MesaGallium.
```

Launch scripts: `scripts/macos-metal/launch-uml-darwin-desktop.sh` and
`launch-in-gui.command`. The CLI default display is VNC on `127.0.0.1:5900`, or `127.0.0.1:5901` when 5900 is already in use (the launcher prints the fallback). Keyboard and pointer events from that VNC server already reach guest evdev (`uml_vnc_input`); labwc must set `WLR_BACKENDS=drm,libinput` (the production default in `start-desktop-labwc.sh`) so wlroots opens those devices. Proof screenshots: `notes/desktop-input-proof/`.
For an AppKit window (and `screencapture -v -l <windowid>`), open the
`.command` from the Mac GUI so `UML_GPU_DISPLAY=native`. Keep the guest at
1920×1080 (`--gpu-auto-resize=off`); do not change the Mac's 3840×2160
display or voxl resize. Use `mem=4G` on the 16 GB mini (the CLI default is
`mem=8G`). Optional `UML_JIT_CACHE_BUDGET=8G` raises the process-wide JIT budget so the shared translation cache can hold one Firefox unique set; evict-on-full is `patches/0011-jit-shared-evict-on-full` (set `UML_JIT_SHARED_STATS=1` on a rebuild to dump hit/miss/reject counters). Packed publication (`patches/0012-jit-publish-alloc`) cuts compile-cold about 5% on a side binary; the official 4K identity is unchanged. `script(1)` in the `.command` gives the guest a pty so
`===DESKTOP_READY===` is line-buffered into `session.log`.

Guest session scripts in `scripts/desktop-guest/` now probe Zink first when
Venus is present, then fall back to virgl. Inject them with `--guest-file`
into `/payload/usr/local/bin/` plus a `/boot.env` with
`UML_BOOT_ROOT_TYPE=ext4` and `UML_BOOT_UPPER=tmpfs`. The kernel command-line
token `init=/uml-per-run-initramfs-did-not-run` is the official canary; it is
expected when the per-run initrd is used.

`patches/0004-map-jit-designed-for-ipad.patch` lets an iphoneos / Designed-for-iPad
build compile the MAP_JIT publication path (`-DUML_IOS_DEBUGGER_JIT=OFF`).
The default on ios remains the debugger-prepared region. Do not install that
build on a physical iPhone.

Look for `Virgl Zink/KosmicKrisp provider: hardware`, cap set id 4 (Venus),
`Darwin native window … (host-page aligned)`, and guest strings containing
`Apple M2 Pro` and `MESA KOSMICKRISP`.

## JIT CPU benches (host vs uml-darwin)

Scripts: `scripts/cpu-benches/`. On the Mac mini, copy that pack to
`~/linux-ios-bakeoff/notes/cpu-benches/` (or point the launcher at it), plus
an optional `apks.tar` of Alpine 3.24 aarch64 `tree`, `openssl`, and
`build-base` (and their dependencies) for an offline `apk add`. The slim
rootfs is `/Volumes/KernariumCS/rootfs/starter-20261112/alpine-3.24.2-minimal.ext4`.

Host:

```
SH_FOR_LOOP=/bin/dash OPENSSL_BIN=/opt/homebrew/opt/openssl/bin/openssl CC=/usr/bin/clang \
  ./scripts/cpu-benches/run-cpu-benches.sh
```

For a gcc-matched tiny-sha, also build and run with Homebrew `gcc-16 -O2`.

Guest: `scripts/cpu-benches/launch-guest-jit-benches.sh` wraps
`uml-darwin --execution-engine=jit` with `mem=2G ncpus=8` and no GPU, under
`caffeinate -i`. Use `script -F` so serial markers are line-buffered and a mid-run profiler reset can see them live. `UML_JIT_PROFILE=1` enables the translated-block exit profiler (`launch-guest-jit-profile.sh sh_loop|compile`). Look for
`===BENCH_START===` / `===BENCH_DONE===`. Results: `scripts/cpu-benches/RESULTS.md`.

