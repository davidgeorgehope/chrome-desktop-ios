#!/bin/bash
# Detached Phase A pipeline for the desktop Views device app. Survives the
# caller going away (run with nohup). Steps:
#   1. wait for build.sh (out/Release-iphoneos-views) to write EXIT; poke.
#   2. on success, sign in the Aqua session via a one-shot LaunchAgent
#      running sign-chrome-views-device.sh; poke.
#   3. run preflight-chrome-views-device.sh; poke with the result.
# Pokes go to the hetzner-event-poke routine webhook via notify-poke.sh.
# Never installs anything on a phone.
set -u
B=$HOME/chromium-build
D=$B/logs/views-device
JOB=chrome-views-device
P=$D/pipeline.status
poke(){ "$B/notify-poke.sh" "$JOB-$1" "$2" "$3" "$4" || true; }
echo "WAIT_BUILD $(date '+%F %T %Z')" > $P
while ! grep -q '^EXIT' $D/build.status 2>/dev/null; do sleep 60; done
rc=$(awk '/^EXIT/{print $2}' $D/build.status | tail -1)
{ cat $D/build.status; echo "failed steps: $(grep -c FAILED: $D/build.log)";
  grep -A3 FAILED: $D/build.log | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'FAILED|error:' | cut -c1-240 | head -20; } > /tmp/views-build-detail.txt
if [ "$rc" != 0 ]; then
  echo "BUILD_FAILED rc=$rc $(date '+%F %T %Z')" >> $P
  poke build BUILD_FAILED "$rc" /tmp/views-build-detail.txt; exit 1
fi
poke build done 0 /tmp/views-build-detail.txt
echo "SIGNING $(date '+%F %T %Z')" >> $P
L=com.davidhope.chrome-views-device-sign
PL=$HOME/Library/LaunchAgents/$L.plist
cat > $PL <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$L</string>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ProcessType</key><string>Interactive</string>
<key>AbandonProcessGroup</key><true/>
<key>RunAtLoad</key><false/>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$B/sign-chrome-views-device.sh</string></array>
<key>StandardOutPath</key><string>$D/sign.launchd.log</string>
<key>StandardErrorPath</key><string>$D/sign.launchd.log</string>
</dict></plist>
PL
echo RUNNING > $D/sign.status
launchctl bootout gui/$(id -u)/$L 2>/dev/null
launchctl bootstrap gui/$(id -u) $PL && launchctl kickstart gui/$(id -u)/$L
for i in $(seq 1 90); do grep -qE '^(done|SIGN_FAILED)' $D/sign.status && break; sleep 20; done
launchctl bootout gui/$(id -u)/$L 2>/dev/null; rm -f $PL
st=$(cat $D/sign.status)
grep -vE '[0-9A-F]{40}' $D/sign.log | tail -40 > /tmp/views-sign-detail.txt
if [ "$st" != done ]; then
  echo "SIGN_FAILED($st) $(date '+%F %T %Z')" >> $P
  poke sign SIGN_FAILED 2 /tmp/views-sign-detail.txt; exit 2
fi
echo "PREFLIGHT $(date '+%F %T %Z')" >> $P
bash $B/preflight-chrome-views-device.sh > $D/preflight.txt 2>&1; prc=$?
if [ $prc -eq 0 ]; then
  echo "READY $(date '+%F %T %Z')" >> $P
  { grep -E '^(INFO|RESULT)' $D/preflight.txt; } > /tmp/views-pre-detail.txt
  poke ipa READY_FOR_DRIVE_STAGING 0 /tmp/views-pre-detail.txt
else
  echo "PREFLIGHT_FAILED $(date '+%F %T %Z')" >> $P
  grep -E '^(FAIL|INFO|RESULT)' $D/preflight.txt > /tmp/views-pre-detail.txt
  poke ipa PREFLIGHT_FAILED $prc /tmp/views-pre-detail.txt; exit 3
fi
