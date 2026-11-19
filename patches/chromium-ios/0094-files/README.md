Name the Command modifier in accelerator text on iOS

Apply after 0093. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
ui::Accelerator::GetLongFormModifiers uses IDS_APP_COMMAND_KEY on iOS like Mac instead of NOTREACHED. Fixes the launch FATAL from VerticalTabStripStateControllerImpl::UpdateCollapseActionItem.

Status (19 Nov 2026, 7:58 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
