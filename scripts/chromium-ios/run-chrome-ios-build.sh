#!/bin/bash
# Builds the iOS Chrome app (//ios/chrome UI on Blink via ios/web/content)
# in the existing use_blink out dir. Resume-safe: just re-run.
set -u
export PATH="$HOME/chromium-build/depot_tools:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
cd "$HOME/chromium-build/chromium/src"
OUT=out/Release-iphonesimulator
LOG=$HOME/chromium-build/logs/chrome-build.log
ST=$HOME/chromium-build/logs/chrome-build.status
J=${JOBS:-8}
echo RUNNING > "$ST"
echo "$(date "+%F %T %Z") START chrome -j$J" >> "$LOG"
if autoninja -C "$OUT" -j "$J" chrome >> "$LOG" 2>&1; then
  echo BUILD_OK > "$ST"; rc=0; s=done
else
  echo BUILD_FAILED > "$ST"; rc=1; s=failed
fi
echo "$(date "+%F %T %Z") END $s" >> "$LOG"
grep -E "FAILED|error:" "$LOG" | tail -20 > /tmp/chrome-build-detail.txt
tail -5 "$LOG" >> /tmp/chrome-build-detail.txt
"$HOME/chromium-build/notify-poke.sh" chromium-ios-chrome-build "$s" "$rc" /tmp/chrome-build-detail.txt
