iOS Views: no unsupported-flag infobar for --single-process

Apply after 0114. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
bad_flags_prompt.cc: under ENABLE_IOS_DESKTOP_VIEWS, switches::kSingleProcess is not in kBadFlags. The iOS Views host always runs single-process (no BrowserEngineKit child-process extensions) and injects the switch itself, so the 'unsupported command-line flag' infobar was misleading. Other bad flags still warn.

Status (19 Nov 2026, 10:55 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
