#!/bin/zsh
# usage: crate-ext-simtest.sh <tag> <pattern:0|1> <WxH> [WxH...]
set -u
S=${SIM_UDID:-booted}
D=${SIM_UDID:-booted}
D2=${SIM_UDID:-booted}
APP=$HOME/linux-ios-bakeoff/dd-crate-sim/Build/Products/Debug-iphonesimulator/Crate.app
OUT=$HOME/linux-ios-bakeoff/screenshots/crate-ext; mkdir -p $OUT
tag=$1; pat=$2; shift 2
xcrun simctl bootstatus $S -b >/dev/null 2>&1
xcrun simctl install $S $APP
for g in "$@"; do
  xcrun simctl io $S screenConfig --display=$D power off >/dev/null 2>&1
  xcrun simctl io $S screenConfig --display=$D2 power off >/dev/null 2>&1
  xcrun simctl terminate $S com.davidhope.crate >/dev/null 2>&1
  if [ $pat != 0 ]; then SIMCTL_CHILD_CRATE_EXTERNAL_TEST_PATTERN=$pat xcrun simctl launch $S com.davidhope.crate >/dev/null
  else xcrun simctl launch $S com.davidhope.crate >/dev/null; fi
  sleep 3
  xcrun simctl io $S screenConfig --display=$D power on >/dev/null 2>&1
  xcrun simctl io $S screenConfig --display=$D geometry $g 2>&1 | head -1
  sleep 4
  xcrun simctl io $S screenshot --display=$D $OUT/$tag-$g.png >/dev/null 2>&1
  c=$(xcrun simctl get_app_container $S com.davidhope.crate data)
  echo "== $g"; grep -E "external display|display:" "$c/Library/Caches/crate.log" | tail -6 | cut -c1-600
done
