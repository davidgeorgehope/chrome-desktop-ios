#!/bin/bash
# Same markers as the Kernarium interactive + gcc_O2 + spawn suites.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/home/cratebench
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
O=/dev/ttyAMA0
[ -e "$O" ] || O=/dev/console
mkdir -p /tmp /var/log "$HOME"
LOG=/var/log/crate-bench.log
if ! touch "$LOG" 2>/dev/null; then
  LOG="$HOME/crate-bench.log"
  touch "$LOG" 2>/dev/null || LOG=/tmp/crate-bench.log
fi
up() { cut -d' ' -f1 /proc/uptime; }
say() { local line="$1"; echo "$line" | tee -a "$LOG" > "$O" 2>/dev/null || echo "$line" >> "$LOG" || true; }

# Wait for the graphical session and packages.
for i in $(seq 1 600); do
  if [ -n "${DISPLAY:-}" ] && command -v xset >/dev/null 2>&1; then
    xset q >/dev/null 2>&1 && break
  fi
  sleep 2
done
say "===DESKTOP_WAIT=== display=${DISPLAY:-none} $(date -u) up=$(up)"

# Packages may still be installing
for i in $(seq 1 900); do
  if [ -f /var/lib/crate/packages-ready ]; then
    break
  fi
  sleep 2
done
say "===PACKAGES=== ready=$(test -f /var/lib/crate/packages-ready && echo 1 || echo 0) chromium=$(command -v chromium || command -v chromium-browser || echo missing) firefox=$(command -v firefox-esr || command -v firefox || echo missing) gcc=$(command -v gcc || echo missing) up=$(up)"

mkdir -p /usr/local/share/interactive-metrics
if [ ! -f /usr/local/share/interactive-metrics/index.html ]; then
  say "===INTERACTIVE_MISSING=== no index.html"
fi
# Start metrics httpd if not up
if ! curl -s -o /dev/null http://127.0.0.1:8765/; then
  python3 /usr/local/bin/metrics-server.py /usr/local/share/interactive-metrics 8765 >/tmp/metrics-httpd.log 2>&1 &
  echo $! > /tmp/metrics-httpd.pid
  for i in $(seq 1 50); do
    curl -s -o /dev/null http://127.0.0.1:8765/ && break
    sleep 0.2
  done
fi
# Ensure serial/log are writable and the metrics httpd is listening before
# any browser cold start (D4 A/B: cr-1 saw ERR_CONNECTION_REFUSED).
chmod a+rw /dev/ttyAMA0 2>/dev/null || true
touch "$LOG" 2>/dev/null || true
chmod a+rw "$LOG" 2>/dev/null || true
if ! curl -s -o /dev/null --max-time 2 http://127.0.0.1:8765/; then
  python3 /usr/local/bin/metrics-server.py /usr/local/share/interactive-metrics 8765 >/var/log/crate-metrics-httpd.log 2>&1 &
  for i in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -o /dev/null --max-time 1 http://127.0.0.1:8765/ && break
    sleep 0.5
  done
fi
say "===INTERACTIVE_ENABLED=== url=http://127.0.0.1:8765/ up=$(up)"
say "===DESKTOP_READY=== $(date -u) up=$(up) display=${DISPLAY} desktop=xfce"

CR_BIN=$(command -v chromium || command -v chromium-browser || true)
FF_BIN=$(command -v firefox-esr || command -v firefox || true)
COMMON="--no-sandbox --password-store=basic --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows --disable-features=CalculateNativeWinOcclusion,IntensiveWakeUpThrottling --start-maximized"
# Xfce is X11; do not force wayland.
CR_FLAGS="$COMMON --disable-gpu-compositing --enable-gpu-rasterization --num-raster-threads=4"
# Clean profile so first-run tabs cannot steal the metrics URL (D4 A/B: firefox
# opened http://basic/ and mozilla.org instead of 127.0.0.1:8765).
FF_PROFILE=/tmp/crate-ff-profile
rm -rf "$FF_PROFILE"
mkdir -p "$FF_PROFILE"
cat > "$FF_PROFILE/user.js" << 'PREF'
user_pref("browser.aboutwelcome.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("app.normandy.first_run", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
PREF
FF_FLAGS="$COMMON --no-remote -profile $FF_PROFILE"

run_browser() {
  local name="$1" bin="$2" flags="$3" tag="$4"
  local url="http://127.0.0.1:8765/"
  if [ -z "$bin" ]; then
    say "===${name^^}_MISSING=== tag=$tag"
    return 1
  fi
  # clear previous done marker by noting start time
  local before
  before=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  say "===${name^^}_START=== $(date -u) up=$(up) from_ready=na bin=$bin tag=$tag url=$url"
  say "===${name^^}_FLAGS=== extra=$flags url=$url"
  # shellcheck disable=SC2086
  $bin $flags "$url" >/tmp/crate-$tag-browser.log 2>&1 &
  local pid=$!
  say "===${name^^}_PID=== $pid tag=$tag up=$(up)"
  # Wait until warm page done or 180s
  local i=0
  while [ $i -lt 180 ]; do
    if [ -f "$LOG" ] && awk -v b="$before" 'NR>b && /===INTERACTIVE_WARM_LAUNCH===/ {found=1} END{exit found?0:1}' "$LOG"; then
      break
    fi
    # also accept input timeout then warm
    if [ -f "$LOG" ] && awk -v b="$before" 'NR>b && /===INTERACTIVE_DONE===/ {found=1} END{exit found?0:1}' "$LOG"; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  say "===${name^^}_WAIT=== tag=$tag secs=$i still=$(kill -0 $pid 2>/dev/null && echo 1 || echo 0) up=$(up)"
  # leave Chromium first-run 1 visible long enough for a host screenshot
  if [ "$tag" = "cr-1" ]; then
    sleep 25
  fi
  kill $pid 2>/dev/null || true
  sleep 2
  kill -9 $pid 2>/dev/null || true
  pkill -f "$bin" 2>/dev/null || true
  sleep 3
  say "===${name^^}_STOP=== tag=$tag up=$(up)"
}

# Give the host a moment after DESKTOP_READY to attach footprint sampling
sleep 8
run_browser chromium "$CR_BIN" "$CR_FLAGS" cr-1
sleep 5
run_browser chromium "$CR_BIN" "$CR_FLAGS" cr-2
sleep 5
run_browser firefox "$FF_BIN" "$FF_FLAGS" ff-1
sleep 5
run_browser firefox "$FF_BIN" "$FF_FLAGS" ff-2

# gcc_O2 + spawn (same workload as guest-gcc-on / guest-spawn)
W=/tmp/w
mkdir -p "$W"
cd "$W"
awk 'BEGIN{print "#include <stdint.h>";
 for(i=0;i<600;i++){printf "uint64_t f%d(uint64_t x,uint64_t y){uint64_t a=x*%d+y;for(int k=0;k<(int)(x&15);k++){switch((a>>k)&7){case 0:a^=a<<13;break;case 1:a+=y*%d;break;case 2:a=(a>>7)|(a<<57);break;case 3:a*=0x9E3779B97F4A7C15ull;break;case 4:a-=x;break;default:a^=%d;}}return a+(y%%%d);}\n",i,i+3,i*7+1,i+11,i+5}
 printf "uint64_t all(uint64_t x){uint64_t s=0;"; for(i=0;i<600;i++)printf "s+=f%d(x,s);",i; print "return s;}"}' > big.c
printf '.globl _start\n_start: mov x0, #0\n mov x8, #93\n svc #0\n' > tiny.S
if gcc -nostdlib -static -o tiny tiny.S >/tmp/tiny-cc.log 2>&1; then
  say "===INFO=== tiny_ok"
else
  # non-static fallback
  gcc -nostdlib -o tiny tiny.S >/tmp/tiny-cc.log 2>&1 || say "===INFO=== tiny_failed $(tr '\n' ' ' < /tmp/tiny-cc.log)"
fi
cat > spawner.c <<'C'
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
int main(int c, char **v) { int n = atoi(v[1]); int mode = atoi(v[2]);
  for (int i = 0; i < n; i++) { pid_t p = fork();
    if (p == 0) { if (mode == 0) _exit(0); execl(v[3], v[3], (char *)0); _exit(127); }
    waitpid(p, 0, 0); } return 0; }
C
gcc -O2 -static -o spawner spawner.c >/tmp/spawner-cc.log 2>&1 || gcc -O2 -o spawner spawner.c >/tmp/spawner-cc.log 2>&1
say "===INFO=== aslr=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null) gcc=$(gcc -dumpversion) cpus=$(nproc) big_c_lines=$(wc -l < big.c)"
t() { n=$1; shift; say "===PHASE=== $n $(up)"; s=$(up); "$@" >/dev/null 2>&1; e=$(up)
  say "===T=== $n $(awk -v a=$s -v b=$e 'BEGIN{printf "%.2f", b-a}')"; }
t gcc_O2_aslr2 gcc -O2 -c big.c -o big.o
t gcc_O2_again_aslr2 gcc -O2 -c big.c -o big.o
if [ -x ./spawner ]; then
  t fork_only_1000_aslr2 ./spawner 1000 0
  if [ -x ./tiny ]; then
    t fork_exec_tiny_1000_aslr2 ./spawner 1000 1 ./tiny
  fi
  t fork_exec_true_1000_aslr2 ./spawner 1000 1 /bin/true
fi
t sh_true_1000_aslr2 sh -c 'i=0; while [ $i -lt 1000 ]; do /bin/true; i=$((i+1)); done'
say "===BENCH_DONE=== $(date -u) up=$(up)"
# keep session up so the host can screenshot / inspect
sleep 60
