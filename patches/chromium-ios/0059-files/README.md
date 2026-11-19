Expose Screen AI, on-device translation, print backend and platform runtime sandboxes to iOS Views

Apply after 0058. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
Desktop Chrome on iOS builds the Screen AI and on-device translation services the way Mac does. Their service mojoms carry ServiceSandbox attributes that name sandbox types sandbox.mojom only enabled on desktop OSes, so the generated interfaces had no kServiceSandbox.

- sandbox.mojom: kPrintBackend, kScreenAI, kPlatformRuntime and kOnDeviceTranslation are also enabled by a new ios_desktop_views mojom feature, set only for is_ios && enable_ios_desktop_views.
- sandbox_type.cc and utility_sandbox_delegate.cc: matching name/type tables and sandbox lists include ENABLE_IOS_DESKTOP_VIEWS.
- sandbox/policy depends on //build:ios_buildflags.

Status (19 Nov 2026, 3:14 AM ET)
--------------------------------
Compile of chrome/browser/ui/views/ios:browser_view_ios continues.
Not BrowserView-on-TVOut yet.

Replace the listed files with the copies in this directory.
