#!/bin/bash
set -eu
export DEBIAN_FRONTEND=noninteractive
LOG=/var/log/crate-packages.log
say() { echo "$1" | tee -a "$LOG" > /dev/ttyAMA0 2>/dev/null || echo "$1" >> "$LOG"; }
say "===APT_START=== $(date -u)"
apt-get update >>"$LOG" 2>&1 || say "===APT_UPDATE_FAIL==="
# Debian 13 names
apt-get install -y --no-install-recommends \
  chromium firefox-esr gcc libc6-dev python3 curl ca-certificates \
  x11-xserver-utils procps >>"$LOG" 2>&1 || \
apt-get install -y \
  chromium firefox-esr gcc libc6-dev python3 curl ca-certificates \
  x11-xserver-utils procps >>"$LOG" 2>&1 || \
  say "===APT_INSTALL_FAIL=== see $LOG"
mkdir -p /var/lib/crate /usr/local/share/interactive-metrics /home/cratebench/.config/autostart
chown -R cratebench:cratebench /home/cratebench/.config /usr/local/share/interactive-metrics 2>/dev/null || true
chmod +x /usr/local/bin/crate-bench.sh /usr/local/bin/metrics-server.py /usr/local/bin/install-packages.sh || true
# If chromium/firefox landed under alternate names, note it
say "===APT_DONE=== chromium=$(command -v chromium || command -v chromium-browser || echo no) firefox=$(command -v firefox-esr || command -v firefox || echo no) gcc=$(command -v gcc || echo no) $(date -u)"

# First-boot correctness: the home dir must be owned by the desktop user
# (cloud-init write_files can leave /home/cratebench as root, which makes
# startxfce4 exit 1). Autologin belongs in user-data, and we also write it
# here in case vendor-data was ignored.
mkdir -p /etc/lightdm/lightdm.conf.d /var/lib/crate /var/log
if [ ! -f /etc/lightdm/lightdm.conf.d/50-autologin.conf ]; then
  cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf << 'EOF'
[Seat:*]
autologin-user=cratebench
autologin-user-timeout=0
autologin-session=xfce
user-session=xfce
EOF
fi
chown -R cratebench:cratebench /home/cratebench || true
touch /var/log/crate-bench.log /var/log/crate-packages.log
chmod a+rw /var/log/crate-bench.log /var/log/crate-packages.log || true
chmod a+rw /dev/ttyAMA0 2>/dev/null || true

# Persist tty/log writability and start the metrics httpd before the desktop
# autostart so Chromium's first cold load has a listener.
cat > /etc/systemd/system/crate-bench-ready.service << 'EOF'
[Unit]
Description=crate bench permissions and metrics httpd
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'chmod a+rw /dev/ttyAMA0 2>/dev/null || true; touch /var/log/crate-bench.log; chmod a+rw /var/log/crate-bench.log; chown -R cratebench:cratebench /home/cratebench'
ExecStart=/bin/bash -c 'if ! curl -s -o /dev/null http://127.0.0.1:8765/; then python3 /usr/local/bin/metrics-server.py /usr/local/share/interactive-metrics 8765 >/var/log/crate-metrics-httpd.log 2>&1 & fi'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload || true
systemctl enable --now crate-bench-ready.service || true

touch /var/lib/crate/packages-ready
