#!/bin/bash
# Simulator-only: icon on the home screen, then an external-display mode change
# while connected (stands in for an AirPlay receiver renegotiating its mode).
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
U=${SIM_UDID:?set SIM_UDID}
T(){ timeout 90 "$@"; }
R=${OUT_DIR:-/tmp/tp-geom-$(date +%H%M%S)}; mkdir -p $R; echo $R > /tmp/tp-geom.last
APP=${APP:?set APP}
BID=com.davidhope.deskbrowser.chromeviews
pkill -x chrome_views_ios; sleep 2
T xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1; sleep 3
T xcrun simctl install $U "$APP"
T xcrun simctl launch $U com.apple.springboard >/dev/null 2>&1
xcrun simctl spawn $U launchctl list >/dev/null 2>&1
sleep 5; T xcrun simctl io $U screenshot --display=LCD $R/0-home.png 2>>$R/err.txt
T xcrun simctl launch --terminate-running-process --stderr=$R/stderr.txt --stdout=$R/stdout.txt $U $BID --no-first-run --no-default-browser-check --hide-crash-restore-bubble https://example.com/ >/dev/null
sleep 40
T xcrun simctl io $U screenConfig --display=TVOut geometry 1920x1080@1 2>>$R/err.txt
T xcrun simctl io $U screenConfig --display=TVOut power on 2>>$R/err.txt
sleep 30; echo "plugged1080 alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=TVOut $R/1-tv1080.png 2>>$R/err.txt
T xcrun simctl io $U screenConfig --display=TVOut geometry 1280x720@1 2>>$R/err.txt
sleep 20; echo "mode720 alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=TVOut $R/2-tv720.png 2>>$R/err.txt
T xcrun simctl io $U screenConfig --display=TVOut geometry 1920x1080@1 2>>$R/err.txt
sleep 20; echo "mode1080 alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=TVOut $R/3-tv1080again.png 2>>$R/err.txt
T xcrun simctl io $U screenshot --display=LCD $R/4-phone.png 2>>$R/err.txt
echo DONE >> $R/steps.txt
