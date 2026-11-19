metagen: honor the build dir's GN root target

Apply after 0132. Used by the separate desktop Views app
(com.davidhope.deskbrowser.chromeviews, out/Release-iphoneos-views and the
simulator). The existing Chromium.app device build keeps
enable_ios_desktop_views off.

What this patch does
--------------------
v8/tools/metagen/compile_flags.py runs `gn desc` in a temporary copy of the build dir, which drops `gn gen --root-target=//chrome/browser/ui/views/ios:chrome_views_ios`. The default "all" graph does not resolve under the desktop Views args (ios/chrome targets need signin_deep_link / cloud_content_scanning that those args leave out), so //v8:run_metagen failed for both toolchains on the fresh device build (out/Release-iphoneos-views). It now reads --root-target from the build dir's build.ninja gn rule and passes it to `gn desc`. No effect on builds without a root target.

Status (19 Nov 2026, 2:11 PM ET)
--------------------------------
Phase A device build in progress (docs/device-build-plan.md).

Replace the listed files with the copies in this directory.
