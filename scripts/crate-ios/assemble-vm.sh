#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
SRC=/tmp/k-harness/crate-images
SETUP=/tmp/k-harness/crate-d4-setup
LOG=/tmp/k-harness/logs/crate-assemble-vm.log
CONTAINER=/Users/davidhope/Library/Containers/FDD810C1-810B-4414-9FB7-3E506CE3509A/Data
APP_SUPPORT="$CONTAINER/Library/Application Support/VMs"
PREF="$CONTAINER/Library/Preferences/com.amendez.crate"
UUID=$(uuidgen)
echo "ASSEMBLE $(date) uuid=$UUID" | tee "$LOG"

# Verify inputs
vmlinuz_sha=$(shasum -a 256 "$SRC/vmlinuz" | awk '{print $1}')
initrd="$SRC/initrd.img"
if [ ! -f "$initrd" ] || [ "$(stat -f%z "$initrd")" != "52080515" ]; then
  if [ -f "$SRC/initrd.img.par" ]; then initrd="$SRC/initrd.img.par"; fi
fi
initrd_sha=$(shasum -a 256 "$initrd" | awk '{print $1}')
xz="$SRC/disk.img.xz.part00"
if [ ! -f "$xz" ] || [ "$(stat -f%z "$xz")" != "610975732" ]; then
  if [ -f "$SRC/disk.img.xz.part00.par" ]; then xz="$SRC/disk.img.xz.part00.par"; fi
fi
xz_sha=$(shasum -a 256 "$xz" | awk '{print $1}')
echo "CHECK vmlinuz=$vmlinuz_sha initrd=$initrd_sha xz=$xz_sha" | tee -a "$LOG"
[ "$vmlinuz_sha" = "0c57da85c644612106cba32d3528151c73b752ad72eb0f20b898f677406e5e65" ]
[ "$initrd_sha" = "19a93c92cb27107ee14f71184c3b683e2a2b43cf0113e9ddb18a473c95ea50b6" ]
[ "$xz_sha" = "b7b1b6bcf39b0b6ad90fd48af28c79bbd93d0c09ae1966b30e70a50967d1e291" ]

GROWN=34359738368
RAW=3489660928
if [ -f "$SRC/disk.img" ] && [ "$(stat -f%z "$SRC/disk.img")" = "$GROWN" ] && [ -f "$SRC/disk.img.verified" ]; then
  echo "DISK_ALREADY_GROWN_VERIFIED $(date)" | tee -a "$LOG"
else
  if [ ! -f "$SRC/disk.img" ] || [ "$(stat -f%z "$SRC/disk.img")" != "$RAW" ]; then
    # If a previous run already grew it without a stamp, do not overwrite.
    if [ -f "$SRC/disk.img" ] && [ "$(stat -f%z "$SRC/disk.img")" = "$GROWN" ]; then
      echo "DISK_ALREADY_32G assume previous verified unpack $(date)" | tee -a "$LOG"
    else
      echo "UNPACK $(date)" | tee -a "$LOG"
      xz -T0 -d -c "$xz" > "$SRC/disk.img"
      raw=$(shasum -a 256 "$SRC/disk.img" | awk '{print $1}')
      rawsz=$(stat -f%z "$SRC/disk.img")
      echo "RAW size=$rawsz sha=$raw" | tee -a "$LOG"
      [ "$raw" = "9fa537d5fe3d5f78a90239061214e0c5b902bcf8b833e5f654e7b4b7bb8466a6" ]
      [ "$rawsz" = "$RAW" ]
    fi
  else
    raw=$(shasum -a 256 "$SRC/disk.img" | awk '{print $1}')
    rawsz=$(stat -f%z "$SRC/disk.img")
    echo "RAW size=$rawsz sha=$raw" | tee -a "$LOG"
    [ "$raw" = "9fa537d5fe3d5f78a90239061214e0c5b902bcf8b833e5f654e7b4b7bb8466a6" ]
    [ "$rawsz" = "$RAW" ]
  fi
  echo "GROW $(date)" | tee -a "$LOG"
  truncate -s "$GROWN" "$SRC/disk.img"
  date > "$SRC/disk.img.verified"
fi
ls -l "$SRC/disk.img" | tee -a "$LOG"
du -h "$SRC/disk.img" | tee -a "$LOG"

# Password hash for a throwaway local VM account (not a user secret)
python3 "$SETUP/make-seed.py" "$SETUP/seed.img" "$UUID" America/New_York cratebench

# Place guest files
# Place guest files
DEST="$APP_SUPPORT/$UUID"
mkdir -p "$DEST"
cp -p "$SRC/vmlinuz" "$DEST/vmlinuz"
cp -p "$initrd" "$DEST/initrd.img"
# move grown disk (saves space vs copy)
mv "$SRC/disk.img" "$DEST/disk.img"
cp -p "$SETUP/seed.img" "$DEST/seed.img"
ls -l "$DEST" | tee -a "$LOG"
echo "$UUID" > "$SETUP/machine-id.txt"

# Encode Machine JSON with Swift so dates/keys match Foundation
cat > "$SETUP/encode-machine.swift" << 'SW'
import Foundation
struct Machine: Codable {
    var id: UUID
    var distributionID: String
    var version: String
    var codename: String?
    var cpuCount: Int
    var memoryGB: Int
    var diskGB: Int
    var diskUsedGB: Double
    var desktop: String
    var display: String
    var architecture: String = "arm64"
    var screenshot: String?
    var lastStarted: Date?
    var imageID: String?
    var cmdline: String?
    var fullWidthInLandscape: Bool?
    var previewDate: Date?
}
let uuid = UUID(uuidString: CommandLine.arguments[1])!
let m = Machine(
    id: uuid,
    distributionID: "debian",
    version: "13",
    codename: nil,
    cpuCount: 4,
    memoryGB: 4,
    diskGB: 32,
    diskUsedGB: 3.489660928,
    desktop: "Xfce",
    display: "1280 × 800",
    screenshot: nil,
    lastStarted: nil,
    imageID: "debian-xfce",
    cmdline: "console=ttyAMA0 root=/dev/vda rw",
    fullWidthInLandscape: true,
    previewDate: nil
)
let data = try JSONEncoder().encode([m])
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try data.write(to: out)
print("wrote \(data.count) bytes")
SW
swiftc -o "$SETUP/encode-machine" "$SETUP/encode-machine.swift"
"$SETUP/encode-machine" "$UUID" "$SETUP/machines.json"
python3 - << PY
import plistlib, pathlib, subprocess, os
pref = pathlib.Path("$PREF.plist")
d = plistlib.loads(pref.read_bytes()) if pref.exists() else {}
d["jit.claiming"] = False
d["jit.codeRegionMB"] = 1024
d["installMemoryGB"] = 4
d["machines"] = pathlib.Path("$SETUP/machines.json").read_bytes()
pref.write_bytes(plistlib.dumps(d, fmt=plistlib.FMT_BINARY))
print("prefs keys", list(d))
print("machines bytes", len(d["machines"]))
PY
# flush cfprefsd
/usr/bin/defaults read "$PREF" jit.codeRegionMB >/dev/null || true
killall -u davidhope cfprefsd 2>/dev/null || true
sleep 1
plutil -p "$PREF.plist" | head -20
echo "ASSEMBLE_OK uuid=$UUID dest=$DEST $(date)" | tee -a "$LOG"
