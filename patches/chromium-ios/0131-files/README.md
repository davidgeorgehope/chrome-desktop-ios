iOS Views: show the key in menu accelerator labels

Apply after 0130. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Accelerator::GetShortcutText only derived the key character (DomCodeToUsLayoutCharacter) for Aura, Mac and Android, so iOS desktop Views menus showed "Ctrl+" with no key. Adds IS_IOS to that branch. Verified in the web context menu: Ctrl+R, Ctrl+S, Ctrl+P, Ctrl+U, Alt+Shift+R. (iOS Views uses the non-Mac accelerator table, hence Ctrl rather than the Command glyph.)

Status (19 Nov 2026, 1:25 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
