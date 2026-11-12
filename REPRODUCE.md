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

`scripts/rebuild-and-relaunch.sh` does cmake, slim packaging, xcodebuild, install, and a console-pty launch. Symlink the ext4 into the app Documents container as shown in NOTES.md. Delete `tmp/kernarium-overlay.ext4` after changing the base image.

If you see `UML: cannot reserve a ... native kernel window` and guest status -4, the window alignment patch is missing or the reservation is not 16 KiB aligned.

## 6. Benches

`scripts/capture-benches.sh` launches with `--console-pty` and waits for `===BENCH_DONE===`. The guest script prints the same suite used for LinuxRunner: `sh` loop 20k, `dd` 32 MiB, `sha256sum`, `apk add tree`, `apk add openssl`, `openssl speed -seconds 3 -evp sha256 aes-256-cbc`.

Typing into `simctl launch --console-pty` did not reliably reach the ttyS0 shell (the PTY echoes but the guest did not execute typed commands). Boot-time script output on the console is the reliable path.

## Phone

Do not install on a physical iPhone until David agrees and a device build has been tested. Device work still needs signing, official iphoneos packaging (KosmicKrisp / Metal 4), and a check that the UML window reserve works on device. Simulator numbers are not device numbers.
