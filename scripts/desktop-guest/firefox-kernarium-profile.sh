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
