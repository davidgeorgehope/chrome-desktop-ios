# crate-ios local bakeoff patches

These are local fixes for the linux-ios-fast crate-ios bakeoff. They are a
patch set, not a vendored copy of crate-ios (MPL-2.0). Do not push the
scratch clone at `linux-ios-bakeoff/scratch/crate-ios` to upstream.

Base: crate-ios tip `7c351b0` (v0.1.3). Apply `0001-local-bakeoff-fixes.patch`
on a clean checkout, then add `Tests/CrateD4Probe/StayAliveTests.swift`.

What the patch carries:

- `RootView` forwards `MachineStore`, `JITSession`, and `MachineRunner` into
  the `fullScreenCover` `MachineScreen`. Designed-for-iPad / iOS 26 can drop
  those `@Observable` environment values otherwise, and Start does nothing.
- Bakeoff-only `--start`: once JIT is on, open and boot the first machine.
  `CRATE_CODE_REGION_MB` can override the code-region size at launch.
- `CRATE_HAS_IOS27_SDK` guards around iOS 27 hinge / toolbar APIs so the
  tree builds with an older SDK.
- Bundle IDs `com.davidhope.crate` / `.jithelper` / `.d4probe`. Upstream
  `com.amendez.crate` cannot be registered to team `4P2629648N` ("not
  available"). The wildcard `iOS Team Provisioning Profile: *` does not
  include `increased-memory-limit` or `extended-virtual-addressing`. An
  explicit App ID profile for `com.davidhope.crate` does (same as Henge,
  LinuxRunner, and Kernarium on this team).
- `Resources/Crate.entitlements` (and the copy here) has `get-task-allow`
  plus both memory entitlements. Do not set `CODE_SIGN_ENTITLEMENTS`
  globally: the JIT helper must not inherit the kernel entitlements.
  Build with `DEVELOPMENT_TEAM=4P2629648N` and `-allowProvisioningUpdates`.

On a 16 Pro (8 GB), the process limit without those entitlements was
~3.54 GB. With them, crate.log reports 6 GiB (6,442,450,944 bytes). A
4 GB guest plus 1024 MB of resident JIT leaves about 1 GiB of headroom
under that cap. If jetsam kills the app, step the guest down to 3.5 GB.

The JIT helper is built-in StikJIT and needs a pairing file at
`Documents/StikJIT/pairingFile.plist` plus a LocalDevVPN tunnel to
`10.7.0.1:49152`. Never commit or print a pairing file.

`CrateD4Probe` is a hosted stay-alive test so an lldb waiter can bless
`brk #0x69` pages on Designed-for-iPad. On a device, built-in StikJIT
does that job instead.
