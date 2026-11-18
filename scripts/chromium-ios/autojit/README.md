# Built-in StikJIT for Blink Chrome

Chrome cannot attach a debugger to itself: the attach stops every thread
of the target, including the one talking to the debugger. A built-in
helper extension (`DeskBrowserJITHelper.appex`) does the attach, the same
shape crate uses.

On launch, `ChromeMain` (before `UIApplicationMain`) reads `Documents/StikJIT/pairingFile.plist` (never
logged or committed), starts the helper through NSExtension, and waits
for `CS_DEBUGGED`. The helper calls `StikJIT.enableJIT` with
`script: .universal` (TXM `brk #0xf00d`) and stays attached so later
Wasm regions can be prepared. If that fails, V8 stays `--jitless` and
Chrome shows a short notice.

`StikJIT.xcframework` is MPL-2.0, fetched by `fetch-stikjit.sh` (pinned
2.0.1). It is not committed. The embed rsync excludes Headers,
PrivateHeaders, and Modules (`0004-stikjit-embed-no-headers` in
crate-ios) so a later copy cannot break the signature (0xe8008017).
Clean helper products before building so a stale StikJIT signature
cannot sneak in.

The helper is signed with `get-task-allow` only and the team wildcard
profile. The main app keeps the explicit
`com.davidhope.deskbrowser.blink` profile (memory entitlements).

The pairing file lives in this app's own Documents container, not
crate's. Copy crate's file there once (Finder file sharing is already
on), and leave LocalDevVPN running. There is no shared app group with
crate, so that copy is the one manual step that cannot be avoided
inside this app alone.
