iOS desktop Views: Chrome web context menu

Apply after 0125. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Replaces the null iOS WebContentsViewDelegate with the shared Views ChromeWebContentsViewDelegateViews and builds RenderViewContextMenuViews for is_ios && enable_ios_desktop_views. Aura-only pieces are gated on USE_AURA: the screen-position client (non-Aura adds WebContents::GetContainerBounds origin) and the WebDragBookmarkHandlerAura drag delegate (nullptr on iOS). WebContentsViewIOS::GetContainerBounds now returns the view's screen rect plus the display offset. RenderViewContextMenu uses the Apple spelling branch on iOS because grit generates only the Mac Language Settings string there. chrome/browser links renderer_context_menu:impl for iOS Views. Verified: two-finger tap on Wikipedia text shows Copy / Copy Link to Highlight / Search Google / Open in Reading Mode / Inspect at the cursor.

Status (19 Nov 2026, 12:35 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
