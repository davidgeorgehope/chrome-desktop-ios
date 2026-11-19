iOS Views: desktop cursor/window lookup and right-button web input

Apply after 0123. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Implements ScreenIos::GetWindowAtScreenPoint and IsWindowUnderCursor for desktop Views, including panel display offsets, visibility, scene state, interaction and level ordering. The trackpad updates ScreenIos cursor state instead of reporting primary-display center. Maps right/middle buttons through RenderWidgetUIView injection (left-only before) and routes web right-clicks to Blink rather than the Views host. Verified DOM events down2/contextmenu/up2. Adds delayed scene-window audit: LCD has phone root and UITextEffectsWindow only; BrowserWidget and cursor overlay live on TVOut. Native Chrome context menu remains pending: the iOS WebContentsViewDelegate returns nullptr. Opening app menu reveals another MenuHost::ShowMenuHost crash to fix next.

Status (19 Nov 2026, 12:14 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
