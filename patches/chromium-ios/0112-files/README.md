iOS Views: cut in-process OnDeviceModelService

Apply after 0111. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
content/utility/services.cc: under ENABLE_IOS_DESKTOP_VIEWS RunOnDeviceModel drops the receiver and returns null. With --single-process the utility runs in the browser process and on_device_model PreSandboxInit is never called, so CHECK(WasPreSandboxInitCalled()) fired a few minutes after launch. mojo::ServiceFactory treats null as no instance; clients see a disconnect.

Status (19 Nov 2026, 10:33 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
