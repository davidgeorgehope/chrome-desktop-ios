# crate-ios external display, mouse, and trackpad (MPL-2.0)

Applies on upstream crate-ios `7c351b0` (v0.1.3). This patch also includes
the earlier local bakeoff fixes (bundle ID `com.davidhope.crate`, `--start`,
iOS 27 SDK guards, CrateD4Probe). It supersedes
`0001-local-bakeoff-fixes.patch` when applied on a clean `7c351b0`.

License: modified and new files stay MPL-2.0. This is our fork/patch set, not
copied into Kernarium. Approach (not source) was taken from Henge's
GPL-2.0 external-display scene, GCMouse, and trackpad design; no Henge files
are included.

Build as `com.davidhope.crate` with `DEVELOPMENT_TEAM=YOURTEAMID` and
`-allowProvisioningUpdates`. Do not push this clone to `oneamendez/crate-ios`.
