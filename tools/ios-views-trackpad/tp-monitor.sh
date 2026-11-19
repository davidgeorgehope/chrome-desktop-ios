#!/bin/bash
# Simulator-only: launch with no monitor, plug TVOut, unplug; screenshot each.
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH
U=${SIM_UDID:-booted}
T(){ timeout 90 "$@"; }
pkill -x chrome_views_ios; sleep 2
T xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1; sleep 3
R=~/chromium-build/logs/views-m2/run/monitor-$(date +%H%M%S); mkdir -p $R; echo $R > /tmp/tp-monitor.last
T xcrun simctl install $U ~/chromium-build/chromium/src/out/Release-iphonesimulator-views/chrome_views_ios.app
T xcrun simctl launch --terminate-running-process --stderr=$R/stderr.txt --stdout=$R/stdout.txt $U com.davidhope.deskbrowser.chromeviews --no-first-run --no-default-browser-check --hide-crash-restore-bubble https://example.com/ >/dev/null
sleep ${W1:-40}; echo "nomon alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=LCD $R/1-nomon.png >/dev/null 2>&1
T xcrun simctl io $U screenConfig --display=TVOut geometry 1920x1080@1 >/dev/null 2>&1
T xcrun simctl io $U screenConfig --display=TVOut power on >/dev/null 2>&1
sleep ${W2:-30}; echo "plugged alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=LCD $R/2-plugged-phone.png >/dev/null 2>&1
T xcrun simctl io $U screenshot --display=TVOut $R/2-plugged-tvout.png >/dev/null 2>&1
T xcrun simctl io $U screenConfig --display=TVOut power off >/dev/null 2>&1
sleep ${W3:-15}; echo "unplugged alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=LCD $R/3-unplugged.png >/dev/null 2>&1
T xcrun simctl io $U screenConfig --display=TVOut power on >/dev/null 2>&1
sleep 20; echo "replugged alive=$(pgrep -x chrome_views_ios >/dev/null && echo 1 || echo 0)" >> $R/steps.txt
T xcrun simctl io $U screenshot --display=TVOut $R/4-replugged-tvout.png >/dev/null 2>&1
echo DONE >> $R/steps.txt
