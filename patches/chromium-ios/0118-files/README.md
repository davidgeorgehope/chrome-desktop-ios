RenderWidgetUIView: don't steal first responder on window move under iOS Views

Apply after 0117. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
-[RenderWidgetUIView didMoveToWindow] called becomeFirstResponder unconditionally. That runs GotFocus -> WebContentsImpl::NotifyWebContentsFocused -> views::WebView::OnWebContentsFocused, which moved Views focus from the just-clicked omnibox back to ContentsWebView, so typed keys found no TextInputClient. Under ENABLE_IOS_DESKTOP_VIEWS it now only becomes first responder if the view already had focus; WebView::OnFocus -> WebContents::Focus still makes it first responder when the page is clicked. Verified: trackpad click on omnibox, type example.com, Return navigates.

Status (19 Nov 2026, 11:27 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
