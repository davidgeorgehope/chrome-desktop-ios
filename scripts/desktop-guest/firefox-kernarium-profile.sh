#!/bin/sh
# Pre-created Firefox profile for the UML desktop.
# Skips the first-run / welcome / telemetry pages. Does not disable the
# content sandbox: under UML that removes the Chroot Helper but does not
# cut time-to-page, shows a warning banner, and one example.com load
# stalled mid-transfer with the sandbox off.
PROFDIR=/root/.mozilla/firefox/kernarium
mkdir -p "$PROFDIR"
cat > /root/.mozilla/firefox/profiles.ini << 'EOI'
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=kernarium
IsRelative=1
Path=kernarium
Default=1
EOI
cat > "$PROFDIR/user.js" << 'EOJ'
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("startup.homepage_override_url", "");
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.page", 0);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.newtabpage.enabled", false);
user_pref("gfx.webrender.all", true);
user_pref("layers.acceleration.force-enabled", true);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
EOJ

# Opt-in lean process model (host drops /usr/local/etc/firefox-lean):
# one content process, no Fission site isolation, no prelaunched spare
# content process, socket and extension work in the parent. Fewer
# processes = less cold-start translation and less guest RAM on a phone.
if [ -f /usr/local/etc/firefox-lean ]; then
  cat >> "$PROFDIR/user.js" << 'EOL'
user_pref("fission.autostart", false);
user_pref("dom.ipc.processCount", 1);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("dom.ipc.processPrelaunch.enabled", false);
user_pref("network.process.enabled", false);
user_pref("extensions.webextensions.remote", false);
EOL
  echo "===FIREFOX_LEAN=== on" | tee /dev/ttyS0 2>/dev/null || true
fi

# Interactive-metrics (and a usable desktop) want a maximized window so
# a mid-tablet evdev poke hits content, not the labwc desktop.
mkdir -p "$PROFDIR"
cat > "$PROFDIR/xulstore.json" << 'EOX'
{"chrome://browser/content/browser.xhtml":{"main-window":{"width":"1920","height":"1080","screenX":"0","screenY":"0","sizemode":"maximized"}}}
EOX
