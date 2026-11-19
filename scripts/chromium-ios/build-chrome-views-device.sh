#!/bin/bash
set -o pipefail
export TMPDIR=/tmp TMP=/tmp
export PATH=$HOME/chromium-build/depot_tools:$PATH
D=$HOME/chromium-build/logs/views-device
cd $HOME/chromium-build/chromium/src
echo "START $(date '+%F %T %Z')" > $D/build.status
autoninja -k 0 -j 8 -C out/Release-iphoneos-views chrome/browser/ui/views/ios:chrome_views_ios >> $D/build.log 2>&1
rc=$?
echo "EXIT $rc $(date '+%F %T %Z')" >> $D/build.status
