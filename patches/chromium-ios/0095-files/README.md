Rasterize vector-icon ImageModels on iOS Views

Apply after 0094. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ui::ImageModel::Rasterize uses ThemedVectorIcon for ENABLE_IOS_DESKTOP_VIEWS (themed_vector_icon is built with use_blink). Fixes the NOTREACHED from LabelButton theming in TabStripFlatEdgeButton; launch now reaches BrowserView::AddedToWidget.

Status (19 Nov 2026, 8:06 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
