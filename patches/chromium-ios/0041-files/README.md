Make desktop //chrome code paths compile for iOS Views.

Apply after 0040. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Adds IOS_MOBILE_UI to build/ios_buildflags.h (is_ios && !enable_ios_desktop_views) and tools/ios-desktop-views/desktopize.py, which switches a component from Chrome-for-iOS code paths to desktop ones under the Views flag. Applied to components/permissions (desktop permission bubbles, not infobars), components/sync/service (desktop UserActionableError set) and components/reading_list/core. Policy code is generated for the Mac platform so policy::key names match desktop. Desktop static_asserts in web_applications accept ENABLE_IOS_DESKTOP_VIEWS, IntranetRedirectDetector builds, the screenshot overlay uses the Views widget layer, cast discovery works without if_arp.h/CoreWLAN, shortcut icon sizes follow Mac, and the translate bubble handles the iOS-only step.

Status (18 Nov 2026, 11:58 PM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
