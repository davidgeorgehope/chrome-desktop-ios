Bundle Chrome's paks into chrome_views_ios.

Apply after 0050. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
chrome_views_ios_paks instantiates chrome_paks with copy_data_to_bundle, as the Mac build does, so resources.pak, the percent paks and <locale>.lproj/locale.pak land in the app bundle. chrome_paks.gni now lists certificate_manager_resources.pak only under chrome_root_store_cert_management_ui, and traces_internals_resources.pak only off iOS, matching the targets that generate them. The chrome libs compile is now capped at -j 6 because the 16 GB mini was swapping.

Status (19 Nov 2026, 1:31 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
