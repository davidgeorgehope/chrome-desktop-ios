iOS Views: route trackpad pointer input only to the active page

Apply after 0126. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
After typing in the omnibox, a prerendered page's RenderWidgetUIView sat in the hit-test path and a trackpad click was injected into it, hitting NOTREACHED (event routed to a prerendered page) in RenderWidgetHostViewBase::ProcessMouseEvent. Adds RenderWidgetHostViewIOS::CanAcceptDesktopPointerInput (host present and not hidden, view showing, frame tree not prerendering) and -[RenderWidgetUIView deskBrowserAcceptsInput]; the mouse and wheel injectors return early when it is false. The trackpad hit-test now replaces a non-accepting web hit with the front-most accepting RenderWidget view under the cursor, falling back to the Views host.

Status (19 Nov 2026, 12:35 PM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
