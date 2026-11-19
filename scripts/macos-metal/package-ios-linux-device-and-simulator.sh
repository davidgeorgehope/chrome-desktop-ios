#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Package Linux ios-device + ios-simulator slices without Android.
# Keeps the Designed-for-iPad device slice while adding Simulator slices.
set -eu
ROOT_DIR=${ROOT_DIR:-$HOME/linux-ios-bakeoff/src/Kernarium}
OUTPUT="$ROOT_DIR/.build/kernarium-xcframeworks"
fail() { printf '%s\n' "package-ios-linux-device-and-simulator.sh: $*" >&2; exit 1; }

DEVICE_RUNTIME="$ROOT_DIR/.build/kernarium-runtime-ios-device/Kernarium/Runtime/KRuntime_6_18_4K.framework"
SIM_RUNTIME="$ROOT_DIR/.build/kernarium-runtime-ios-simulator/Kernarium/Runtime/KRuntime_6_18_4K.framework"
DEVICE_GPU_PREFIX="$ROOT_DIR/.build/dependencies/apple-gpu-vulkan-experiment/ios-device-arm64"
SIM_GPU_PREFIX="$ROOT_DIR/.build/dependencies/apple-gpu-vulkan-experiment/ios-simulator-arm64"
DEVICE_GPU="$DEVICE_GPU_PREFIX/Frameworks"
SIM_GPU="$SIM_GPU_PREFIX/Frameworks"
STORAGE="$ROOT_DIR/.build/dependencies/ios-storage/GPTFDisk.xcframework"
ZSTD="$ROOT_DIR/.build/dependencies/ios-zstd/LibZstd.xcframework"
DEVICE_BATTERY="$ROOT_DIR/.build/kernarium-runtime-ios-device/darwin/platform/libuml_host_battery.a"
SIM_BATTERY="$ROOT_DIR/.build/kernarium-runtime-ios-simulator/darwin/platform/libuml_host_battery.a"
HOST_BATTERY_HEADER="$ROOT_DIR/darwin/platform/host_battery.hpp"
DEVICE_VIDEO="$ROOT_DIR/.build/kernarium-runtime-ios-device/darwin/platform/libuml_video_encoder.a"
SIM_VIDEO="$ROOT_DIR/.build/kernarium-runtime-ios-simulator/darwin/platform/libuml_video_encoder.a"
HOST_VIDEO_HEADERS="$ROOT_DIR/darwin/platform/video_encoder.hpp $ROOT_DIR/darwin/platform/video_decoder.hpp"
PRIVACY="$ROOT_DIR/Kernarium/PrivacyManifests"

for p in "$DEVICE_RUNTIME" "$DEVICE_RUNTIME.dSYM" \
	"$SIM_RUNTIME" "$SIM_RUNTIME.dSYM" \
	"$DEVICE_GPU/KosmicKrisp.framework" "$DEVICE_GPU/MesaEGL.framework" \
	"$DEVICE_GPU/MesaGallium.framework" \
	"$SIM_GPU/MesaEGL.framework" "$SIM_GPU/MesaGallium.framework" \
	"$DEVICE_GPU_PREFIX/dSYMs/KosmicKrisp.framework.dSYM" \
	"$DEVICE_GPU_PREFIX/dSYMs/MesaEGL.framework.dSYM" \
	"$DEVICE_GPU_PREFIX/dSYMs/MesaGallium.framework.dSYM" \
	"$SIM_GPU_PREFIX/dSYMs/MesaEGL.framework.dSYM" \
	"$SIM_GPU_PREFIX/dSYMs/MesaGallium.framework.dSYM" \
	"$STORAGE" "$ZSTD" \
	"$DEVICE_BATTERY" "$SIM_BATTERY" "$DEVICE_VIDEO" "$SIM_VIDEO" \
	"$HOST_BATTERY_HEADER"; do
	[ -e "$p" ] || fail "missing: $p"
done

OUTPUT_PARENT=$(dirname -- "$OUTPUT")
mkdir -p -- "$OUTPUT_PARENT"
STAGE=$(mktemp -d "$OUTPUT_PARENT/.kernarium-xcframeworks.XXXXXX")
cleanup() {
	if [ -n "${STAGE:-}" ] && [ -d "$STAGE" ]; then
		rm -rf "$STAGE"
	fi
}
trap cleanup EXIT HUP INT TERM

create_fw_device_sim() {
	name=$1
	dev=$2
	dev_dsym=$3
	sim=$4
	sim_dsym=$5
	xcodebuild -create-xcframework \
		-framework "$dev" -debug-symbols "$dev_dsym" \
		-framework "$sim" -debug-symbols "$sim_dsym" \
		-output "$STAGE/$name.xcframework"
	[ -f "$STAGE/$name.xcframework/Info.plist" ] || fail "failed to create $name"
}

create_fw_device_only() {
	name=$1
	framework=$2
	symbols=$3
	xcodebuild -create-xcframework \
		-framework "$framework" -debug-symbols "$symbols" \
		-output "$STAGE/$name.xcframework"
	[ -f "$STAGE/$name.xcframework/Info.plist" ] || fail "failed to create $name"
}

create_fw_device_sim KRuntime_6_18_4K \
	"$DEVICE_RUNTIME" "$DEVICE_RUNTIME.dSYM" \
	"$SIM_RUNTIME" "$SIM_RUNTIME.dSYM"
create_fw_device_sim MesaEGL \
	"$DEVICE_GPU/MesaEGL.framework" "$DEVICE_GPU_PREFIX/dSYMs/MesaEGL.framework.dSYM" \
	"$SIM_GPU/MesaEGL.framework" "$SIM_GPU_PREFIX/dSYMs/MesaEGL.framework.dSYM"
create_fw_device_sim MesaGallium \
	"$DEVICE_GPU/MesaGallium.framework" "$DEVICE_GPU_PREFIX/dSYMs/MesaGallium.framework.dSYM" \
	"$SIM_GPU/MesaGallium.framework" "$SIM_GPU_PREFIX/dSYMs/MesaGallium.framework.dSYM"
create_fw_device_only KosmicKrisp \
	"$DEVICE_GPU/KosmicKrisp.framework" "$DEVICE_GPU_PREFIX/dSYMs/KosmicKrisp.framework.dSYM"

install_privacy() {
	name=$1
	manifest=$2
	found=0
	for slice_framework in "$STAGE/$name.xcframework"/*/"$name.framework"; do
		[ -d "$slice_framework" ] || continue
		found=1
		cp -- "$PRIVACY/$manifest.xcprivacy" "$slice_framework/PrivacyInfo.xcprivacy" ||
			fail "privacy manifest for $name"
	done
	[ "$found" -eq 1 ] || fail "$name has no framework slice"
}

strip_maps() {
	name=$1
	for slice_framework in "$STAGE/$name.xcframework"/*/"$name.framework"; do
		[ -f "$slice_framework/$name" ] || fail "no binary in $slice_framework"
		strip -S "$slice_framework/$name" || fail "strip $slice_framework"
	done
}

for name in KRuntime_6_18_4K MesaEGL MesaGallium KosmicKrisp; do
	strip_maps "$name"
done
install_privacy KRuntime_6_18_4K KRuntime
install_privacy MesaEGL MesaEGL
install_privacy MesaGallium MesaGallium
install_privacy KosmicKrisp KosmicKrisp

# Device slice: kernel symbols live in the dSYM, not the stripped binary
symbols="$STAGE/KRuntime_6_18_4K.xcframework/ios-arm64/dSYMs/KRuntime_6_18_4K.framework.dSYM/Contents/Resources/DWARF/KRuntime_6_18_4K"
binary="$STAGE/KRuntime_6_18_4K.xcframework/ios-arm64/KRuntime_6_18_4K.framework/KRuntime_6_18_4K"
[ -f "$symbols" ] || fail "missing runtime dSYM dwarf"
nm -a "$symbols" | LC_ALL=C grep -q ' ___uml_kernel_symbols$' ||
	fail "dSYM does not name the kernel functions"
if nm -a "$binary" | LC_ALL=C grep -q ' ___uml_kernel_symbols$'; then
	fail "runtime binary still carries kernel function symbols"
fi

cp -R "$STORAGE" "$STAGE/GPTFDisk.xcframework"
cp -R "$ZSTD" "$STAGE/LibZstd.xcframework"

create_archive_device_sim() {
	name=$1
	shift
	headers="$STAGE/$name-headers"
	mkdir -p -- "$headers"
	while [ "$1" != -- ]; do
		cp -- "$1" "$headers/"
		shift
	done
	shift
	devlib=$1
	simlib=$2
	xcodebuild -create-xcframework \
		-library "$devlib" -headers "$headers" \
		-library "$simlib" -headers "$headers" \
		-output "$STAGE/$name.xcframework"
	rm -rf "$headers"
	[ -f "$STAGE/$name.xcframework/Info.plist" ] || fail "failed to create $name"
}
create_archive_device_sim HostBattery "$HOST_BATTERY_HEADER" -- "$DEVICE_BATTERY" "$SIM_BATTERY"
# shellcheck disable=SC2086
set -- $HOST_VIDEO_HEADERS
create_archive_device_sim HostVideoEncoder "$@" -- "$DEVICE_VIDEO" "$SIM_VIDEO"

# Platform 2 = iOS device, 7 = Simulator
platform_of() {
	otool -l "$1" | awk '
		$1 == "cmd" { command = $2; next }
		command == "LC_BUILD_VERSION" && $1 == "platform" { print $2; exit }
	'
}
for framework in KRuntime_6_18_4K MesaEGL MesaGallium KosmicKrisp; do
	binary="$STAGE/$framework.xcframework/ios-arm64/$framework.framework/$framework"
	[ -f "$binary" ] || fail "missing device binary $binary"
	platform=$(platform_of "$binary")
	[ "$platform" = "2" ] || fail "$framework device is platform $platform, not 2"
done
for framework in KRuntime_6_18_4K MesaEGL MesaGallium; do
	binary="$STAGE/$framework.xcframework/ios-arm64-simulator/$framework.framework/$framework"
	[ -f "$binary" ] || fail "missing simulator binary $binary"
	platform=$(platform_of "$binary")
	[ "$platform" = "7" ] || fail "$framework simulator is platform $platform, not 7"
done
[ ! -e "$STAGE/KosmicKrisp.xcframework/ios-arm64-simulator" ] ||
	fail "KosmicKrisp unexpectedly has a Simulator slice"

for framework in KRuntime_6_18_4K MesaEGL MesaGallium KosmicKrisp; do
	python3 -B "$ROOT_DIR/scripts/check-software-renderer.py" --absent \
		"$STAGE/$framework.xcframework/ios-arm64" ||
		fail "device slice of $framework carries the software renderer"
	python3 -B "$ROOT_DIR/scripts/check-privacy-manifests.py" \
		"$STAGE/$framework.xcframework/ios-arm64/$framework.framework" ||
		fail "privacy manifest check failed for $framework"
done
# Simulator slices may carry the software renderer.
for framework in KRuntime_6_18_4K MesaEGL MesaGallium; do
	python3 -B "$ROOT_DIR/scripts/check-privacy-manifests.py" \
		"$STAGE/$framework.xcframework/ios-arm64-simulator/$framework.framework" ||
		fail "privacy manifest check failed for simulator $framework"
done

for platform in ios-arm64 ios-arm64-simulator; do
	[ -f "$STAGE/GPTFDisk.xcframework/$platform/GPTFDisk.framework/GPTFDisk" ] ||
		fail "missing GPTFDisk $platform"
	[ -f "$STAGE/LibZstd.xcframework/$platform/LibZstd.framework/LibZstd" ] ||
		fail "missing LibZstd $platform"
done

python3 -B "$ROOT_DIR/scripts/check-no-fexcore.py" "$STAGE" ||
	fail "a packaged iOS framework carries FEXCore"

publish=0
python3 "$ROOT_DIR/dependencies/publish-prefix.py" "$STAGE" "$OUTPUT" || publish=$?
case $publish in
0) STAGE= ;;
1)
	publish=0
	python3 "$ROOT_DIR/dependencies/publish-prefix.py" --swap "$STAGE" "$OUTPUT" || publish=$?
	[ "$publish" -eq 0 ] || fail "could not replace published XCFrameworks"
	if [ -L "$STAGE" ]; then
		rm -f -- "$STAGE"
		STAGE=
	fi
	;;
*) fail "could not publish XCFrameworks" ;;
esac
printf '%s\n' "published Linux ios-device+simulator XCFrameworks (no Android runtime): $OUTPUT"
ls -d "$OUTPUT"/*.xcframework
