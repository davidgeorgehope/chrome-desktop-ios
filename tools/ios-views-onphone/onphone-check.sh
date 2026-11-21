#!/bin/bash
# Simulator-only: on-phone desktop check (0142). Launch with no monitor, pinch,
# long-press, omnibox + keyboard, navigate, then plug and unplug TVOut.
# Needs axe (brew install axe). SIM_UDID: an iPhone simulator.
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
U=${SIM_UDID:?set SIM_UDID}
APP=${APP:-$HOME/chromium-build/chromium/src/out/Release-iphonesimulator-views/chrome_views_ios.app}
T(){ timeout 120 "$@"; }
R=${OUT_DIR:-/tmp/onphone-$(date +%H%M%S)}; mkdir -p $R; echo $R > /tmp/onphone.last
S(){ sleep ${2:-3}; T xcrun simctl io $U screenshot $R/$1.png >/dev/null 2>&1; echo "$1 alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt; }
T xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1
pkill -x chrome_views_ios; sleep 2
T xcrun simctl install $U "$APP"
T xcrun simctl launch --terminate-running-process --stderr=$R/stderr.txt --stdout=$R/stdout.txt $U com.davidhope.deskbrowser.chromeviews --no-first-run --no-default-browser-check https://github.com/ >/dev/null
S 1-github 45
T axe gesture pinch --scale 2.5 -x 250 -y 150 --udid $U >/dev/null; S 2-zoom 3
T axe gesture pinch --scale 0.2 --udid $U >/dev/null; sleep 2
T axe touch -x 450 -y 250 --down --up --delay 1.0 --udid $U >/dev/null; S 3-rightclick 2
# Use axe tap (not touch --down --up) for taps: after a long press the latter
# arrives late enough to read as another long press.
T axe tap -x 150 -y 350 --udid $U >/dev/null; sleep 2
T axe tap -x 300 -y 39 --udid $U >/dev/null; S 4-omnibox-keyboard 2
T axe type "youtube.com" --udid $U >/dev/null; sleep 1; T axe key 40 --udid $U >/dev/null
S 5-youtube 25
T xcrun simctl io $U screenConfig --display=TVOut geometry 1920x1080@1 >/dev/null 2>&1
T xcrun simctl io $U screenConfig --display=TVOut power on >/dev/null 2>&1
S 6-monitor-phone 30
T xcrun simctl io $U screenshot --display=TVOut $R/6-monitor-tvout.png >/dev/null 2>&1
T xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1
S 7-unplugged 15
grep -a "desktop mode\|phone desktop" $R/stderr.txt | sed 's/.*\[DeskBrowser\] //' >> $R/steps.txt
echo DONE >> $R/steps.txt
