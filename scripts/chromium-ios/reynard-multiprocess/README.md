# Reynard-style multi-process renderer (stretch, behind a flag)

This is not enabled in the default device Chrome build. BrowserEngineKit
child-process entitlements are unavailable for this team, and
`fork`/`posix_spawn` are not allowed for a sideloaded iOS app.
LiveContainer also cannot host app extensions.

Reynard (https://github.com/minh-ton/reynard-browser) shows a working
non-BEK path on stock-signed sideloads:

- Child processes are an app extension whose `NSExtensionPointIdentifier`
  is `com.apple.ar.viewer` with `NSExtensionActivationRule = FALSEPREDICATE`.
- The extension's `XPCService` dictionary is
  `ServiceType=Application`, `_MultipleInstances=true`, `_ProcessType=App`.
- The helper is signed with `get-task-allow` only; the main app keeps
  `increased-memory-limit`.
- Instances are started with the private `NSExtension
  extensionWithIdentifier:` / `beginExtensionRequestWithInputItems:`.
  The raw libxpc connection is taken from `NSXPCConnection._xpcConnection`
  and used as the IPC transport.
- Graphics are passed as IOSurfaces (no `BELayerHierarchy`).
- Installers must keep app extensions (the current
  `sign-chrome-ios-device-mem.sh` strips `PlugIns/` and `Extensions/`).

## Flag

Runtime / GN flag (off by default):

```
# chrome-ios-device.args.gn
deskbrowser_enable_reynard_renderer = false
```

When this is flipped, the work that still has to be done in Chromium is:

1. A helper appex target with the `com.apple.ar.viewer` Info.plist above
   and its own bundle id under `com.davidhope.deskbrowser.blink.*`.
2. A process launcher that replaces the BEK
   `BEWebContentProcess makeLibXPCConnectionError:` path with an
   NSExtension-backed libxpc connection.
3. Mojo + shared-memory / Mach-port bootstrap over that connection, plus
   IOSurface for compositing (the in-process CALayer fallback in patch
   0001 stays for the single-process default).
4. Sign and pack the helper (do not strip PlugIns when the flag is on).
5. Optional: attach StikJIT / a built-in idevice client to each child PID
   so TXM JIT works in the renderer, not only in the browser process.

Until that lands, the device build stays single-process
(`--single-process --in-process-gpu`) with the TXM JIT helper, memory
entitlements, DrumBrake, and jetsam hardening.
