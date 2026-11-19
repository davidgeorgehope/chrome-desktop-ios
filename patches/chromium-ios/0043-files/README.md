Desktopize password manager, signin, lens and send-tab components for iOS Views.

Apply after 0042. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Runs desktopize.py on components/password_manager/core, components/signin, components/lens, components/qr_code_generator and components/send_tab_to_self so //chrome desktop UI sees the desktop APIs (password bubbles, Dice-style signin, lens bitmap helpers). Narrows the desktop #if widening to lists that include Linux or ChromeOS (Win+Mac-only gates guard OS integrations and are reverted). Small iOS fixes: Mac keybindings for extension commands, WebRTC log product, no native-messaging dirs, devtools policy dialog and desktop capture skip NativeWindow lookups, and the unhandled keyboard handler copes with the iOS NativeEvent variant. Args (scripts/chromium-ios/args-views-simulator.gn) turn on WebUI NTP/history/bookmarks and the message center like Mac, and set enable_printing_tests = false so ENABLE_PRINTING matches enable_printing.

Status (19 Nov 2026, 12:05 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
