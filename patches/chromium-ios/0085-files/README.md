Port Widget::CloseAllWidgets; build platform-neutral desktop pieces on iOS Views

Apply after 0084. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
native_widget_ios.mm: Widget::CloseAllWidgets closes every top-level NativeWidgetIOS (snapshot of the window map, re-looked-up per close). GN parity with Mac/Android for: autofill cross_tab_copy_paste_tracker, sync_bookmarks initial_account_bookmark_deduplicator, extension_install_ui_desktop, supervised_user linux_mac_windows sources, enterprise connectors common.cc/content_analysis_info.cc and connectors reporting impl (realtime reporting client). GN gen passes; compile verified in the next step.

Status (19 Nov 2026, 6:54 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
