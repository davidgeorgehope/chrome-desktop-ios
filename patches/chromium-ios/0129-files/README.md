iOS Views: wait for pref rundown in EndSession

Apply after 0128. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
On SIGTERM (application_lifetime_desktop SessionEnding) BrowserProcessImpl::EndSession hit NOTIMPLEMENTED on iOS and returned without waiting, so pending Preferences/Local State writes were lost and metrics saw a crash. Adds IS_IOS to the platforms that define kEndSessionTimeout and TimedWait on the rundown counter, matching Mac. Verified on the simulator: both files are written at kill time and Local State user_experience_metrics.stability.exited_cleanly is true. The profile exit_type keeps the earlier Crashed value while ExitTypeService waits for the crash bubble to be acknowledged, which is upstream behaviour.

Status (19 Nov 2026, 12:49 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
