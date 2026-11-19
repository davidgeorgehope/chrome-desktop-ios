# Desktop Chrome on iPhone (external monitor)

**Decision (18 Nov 2026, 2:43 PM ET):** port desktop Chrome’s Views
interface (`//chrome/browser/ui/views`: tab strip, toolbar, omnibox,
app menu, bookmarks bar, settings via WebUI) to iPhone, rendered on
the connected monitor, even if it takes weeks.

This document is the Phase 1 feasibility plan and milestone map. It is
written against the Chromium tree at `~/chromium-build/chromium/src`
on the Mac mini, `use_blink=true`, jitless-by-default Blink Chrome
already shipping as `com.davidhope.deskbrowser.blink`.

## Goal

When the iPhone is plugged into a monitor, the monitor should show a
real desktop Chrome window — the same Views chrome you get from
Chromium on a desktop — not a stretched or regular-size-class copy of
`//ios/chrome` UIKit. The phone is a control surface (and the pointer
target, because iPhone iOS 27 has no interactive external-display
role). Keyboard input attached to the phone should type into the
desktop window.

## Architecture: follow Mac, not Linux

| Layer | Windows / Linux | Mac today | iOS today | iOS target |
| --- | --- | --- | --- | --- |
| Toolkit | Views | Views | UIKit `//ios/chrome` | Views |
| Windowing | Aura + Ozone (Wayland/X11/DRM) | `NativeWidgetMac` / AppKit, **no Aura** | UIWindow / UIView | **`NativeWidgetIOS` / UIKit, no Aura** |
| `gfx::NativeWindow` | `aura::Window*` | `WeakNSWindow` | `WeakUIWindow` (already) | keep UIKit types |
| Display | Ozone / Screen | AppKit Screen | `ui/display/ios/screen_ios.mm` (already) | extend for external `UIScreen` / scene |
| Compositor output | Ozone surface | `ui/accelerated_widget_mac` CALayer | builds, but **offscreen only** | on-screen CALayer / Metal in a UIWindow |
| Browser UI | `chrome/browser/ui/views` | same | `ios/chrome` UIKit | `chrome/browser/ui/views` |
| Web contents | Blink / content | Blink / content | Blink via `ios/web/content` | Blink / content hosted in a Views widget |

**Do not start with a new Ozone platform or Aura on iOS.** Ozone
currently has wayland, x11, drm, headless, cast, and flatland — no
UIKit. Aura would also change `NativeWindow` to `aura::Window*`,
fighting the types iOS already uses. Mac already proves Views can
host a full BrowserView without Aura.

The missing platform piece is a UIKit-backed `NativeWidget` plus an
**on-screen** compositor path into a `CALayer` (or Metal layer) on a
`UIWindow`, including the external-display window.

## What already exists (prior art)

- **Official Chrome iOS on Blink** (Igalia / Google, 2024–): reuses
  the existing UIKit `//ios/chrome` UI and implements `//ios/web`
  public APIs with Blink (`ContentWebState`). It is explicitly *not*
  a Views/Aura port. That is the tree we have been shipping.
- **`content_shell` on iOS**: a real Content/Blink embedder with a
  UIKit URL bar (`shell_platform_delegate_ios.mm`,
  `shell_application_ios.mm`). Already builds in
  `out/Release-iphonesimulator`. Useful as a WebContents host, not as
  desktop chrome. `shell_use_toolkit_views` is `toolkit_views &&
  !is_castos` and therefore false on iOS today.
- **`ui/views_content_client`**: a small Views+content embedder with
  Mac and Aura main-parts. A good Milestone 2 stepping stone, lighter
  than all of `//chrome`.
- **`ui/compositor` on iOS**: already compiles. The test host
  (`test_compositor_host_ios.mm`) is offscreen:
  `SetAcceleratedWidget(gfx::kNullAcceleratedWidget)` with a TODO to
  “Support onscreen here.”
- **`ui/accelerated_widget_mac`**: CALayer frame-sink code already
  has iOS sources (`ca_layer_frame_sink_provider`) and
  `display_ca_layer_tree` on the *simulator* only
  (`is_ios && target_platform != "iphoneos"`). Device (iphoneos)
  still needs that path, possibly via BrowserEngineKit.
- **`ui/display/ios/screen_ios.mm`**: already lists `UIScreen`s
  from connected `UIWindowScene`s.
- **No public fork** found that ships desktop Views Chrome on
  iPhone. Ozone/headless is for tests, not a monitor.

## Hard gates in the tree

1. `assert(!is_ios)` in `//chrome/BUILD.gn` and `//chrome/test/BUILD.gn`:
   the entire desktop Chrome target is excluded from iOS. This is the
   main Milestone 2 wall.
2. `toolkit_views` defaults off on iOS (`build/config/ui.gni`).
   `use_aura` stays off (Mac-style).
3. `tools/grit/grit_args.gni` asserts
   `toolkit_views == (is_chromeos \|\| is_fuchsia \|\| is_linux \|\|
   is_mac \|\| is_win)`. This must be widened behind a flag.
4. Turning `toolkit_views` on for an iOS `gn gen` pulls a
   desktop-only graph (root `BUILD.gn` `views_examples`,
   `watermark_app` → `//chrome/test`, `components/web_modal` which
   itself `assert(!is_android && !is_ios)`,
   `components/constrained_window`, `enable_library_cdms` / CDM
   paths, …). Each of these has to be gated or stubbed. This is a
   GN garden, not a single-line flip.
5. `NativeWidgetPrivate::CreateNativeWidget` exists only for Aura and
   Mac. There is no iOS implementation.
6. Desktop Chrome’s process model is multi-process. On iOS we will
   keep the already-working **single-process + in-process GPU**
   content path (`--single-process`, `--in-process-gpu`,
   `NetTaskScheduler` off), jitless by default, existing memory
   entitlements and heap cap. JIT stays parked behind the hidden
   flag.
7. **Input:** map UIKit pointer and keyboard events into `ui::Event`
   / Views. iPhone iOS 27 has no interactive external-display scene
   role (`UISceneAccessory` is `externalNonInteractive` only). Mouse
   clicks *on the monitor* may not be delivered; the phone is the
   pointer surface. A hardware keyboard should target the external
   window when it is key.
8. **External display:** iOS 27 does not give Stage Manager on
   iPhone. The proper API is
   `UISceneAccessory.externalNonInteractive` plus
   `UIWindowSceneSessionRoleExternalDisplayNonInteractive`. Info.plist
   alone is not enough on iOS 27; without a successful accessory (or
   a window moved onto `UIScreen.mirroredScreen`) the system **mirrors
   the phone UI**. That is the bug we saw on the real Dopesplay
   monitor. The Simulator (iOS 26.5) still creates the external
   scene from the plist, which is why sim pre-check looked fine
   while the device kept mirroring.

## What to stub (Milestone 2–4)

Keep, or reuse from `//components`:

- Bookmarks, history, most WebUI (`chrome://settings` as a first
  settings surface), a single profile, locate-in-page, find bar.

Stub, disable, or defer:

- Chrome updater / Omaha / enterprise companion
- Desktop extensions and native messaging (optional later)
- Profile picker / multiple profiles
- Printing, cryptohome, desktop notifications, component-updated
  CDMs (`enable_library_cdms` stays false)
- Safe-browsing / sync: only after a basic BrowserView loads pages
- Anything that assumes a separate GPU or renderer process

## iOS cut list (re-enable later)

Things cut, stubbed, or narrowed on `is_ios && enable_ios_desktop_views`
to get `chrome_views_ios` to link and launch. Each line names the patch
and what re-enabling it would take. Real ports (not cuts) are listed
under "iOS ports" below.

| Patch | Area | What iOS does now | To re-enable |
|---|---|---|---|
| 0068 | `platform_util` show-in-folder / open item | no-op | Files app / `UIDocumentInteractionController` |
| 0070 | Create app shortcut dialog | callback(false) | web app OS integration on iOS |
| 0071 | Device reauth (password manager) | never available, auth fails | `LAContext` authenticator |
| 0071 | OS crypt | posix obfuscation key provider only | Keychain key provider |
| 0072 | Profile picker hide at shutdown | skipped | build profile picker (below) |
| 0072 | Native notifications bridge | null, message center fallback | `UNUserNotificationCenter` bridge |
| 0072 | First run (initial prefs, EULA, relaunch) | no-op / false | first run flow on iOS |
| 0073 | Web contents view delegate (context menus) | null delegate | Views render context menu without Aura |
| 0073 | AI overlay, headless metrics | built, unused | n/a |
| 0074 | Process singleton | always creates, no IPC | not needed (one process per app) |
| 0074 | Gapis service | narrowed to Linux/Mac | build `//chrome/browser/gapis` |
| 0074 | WhatsNew registry, scheduled restart manager | nullptr | build WhatsNew / scheduled restart |
| 0074 | chrome://apps (AppHome) | not registered | build `webui/app_home` |
| 0077 | Chrome Apps windows | `CreateNativeAppWindowImpl` returns null | `ChromeNativeAppWindowViews` iOS subclass |
| 0077 | Desktop capture window icons | empty image | not possible on iOS |
| 0077 | Storage monitor (removable media) | dummy | not needed |
| 0077 | Download quarantine | generic no-op (OK) | file protection attributes |
| 0078 | Profile picker window | `ProfilePicker` statics no-op, startup mode always browser window | build `views/profiles` picker + `webui/signin:profile_impl` |
| 0078 | Profile picker / customization / managed notice WebUIs | configs and binders not registered | same as above |
| 0078 | Default browser modal WebUI | not registered, target out of graph | build `default_browser_prompt` |
| 0078 | WhatsNew, web app settings, on-device translation internals, history sync opt-in, chrome://apps binders | not registered | build those WebUI targets |
| 0079 | Default browser prompt (infobar, app menu item, action, prefs) | not shown / not registered | build `startup/default_browser_prompt` |
| 0079 | Scheduled restart (menu item, icon badge, bubble, NTP nudge, prefs) | narrowed to Win/Mac/Linux | build `views/scheduled_restart` + relaunch |
| 0079 | WhatsNew startup fetch + local state prefs | narrowed to Win/Mac/Linux | build `webui/whats_new` |
| 0079 | Session restore infobar (controller, registry, internals) | narrowed / returns false | build `views/session_restore_infobar` |
| 0079 | Create desktop shortcut | command disabled | `ui/shortcuts` on iOS |
| 0079 | Settings handlers: default browser, manage profile, system | not added | build those handlers |
| 0080 | Platform policy provider | null (no managed app config) | `PolicyLoaderIOS` |
| 0080 | Policies: browser switcher, enterprise skills, memory saver / search aggregator / site search, guest mode / local sync / theme color, Gemini URL, battery saver | handlers not registered | build the handlers' targets |
| 0080 | Browser switcher, enterprise signin profile prefs | not registered | build `browser_switcher`, `enterprise/signin` |
| 0081 | First run experience (FirstRunService, startup FRE, prefs) | not created, startup opens the browser directly | FRE on iOS |
| 0081 | Profile/signin services: accounts policy manager, profile management disclaimer, token / OIDC signin interceptors and policy services, enterprise signin, browser switcher, Gapis | factories not created | build those targets |
| 0081 | `--list-apps` web app file writer | narrowed | n/a |
| 0082 | `webAuthenticationProxy` extension API | API not generated, no proxy | build the API + service |
| 0082 | `networkingPrivate` UI delegate | factory not registered | Wi-Fi/network UI delegate for iOS |
| 0082 | Captive portal Wi-Fi SSID lookup | SSID left empty (generic captive portal page) | `wifi::WiFiService` for iOS |

## iOS ports

| Patch | Piece |
|---|---|
| 0075 | `views::EventMonitor` (`event_monitor_ios.mm`) |
| 0077 | `NativeViewHostIOS` (hosts WebContents `UIView` in the widget) |
| 0077 | `UnhandledKeyboardEventHandler` (Views accelerators from web keys) |
| 0077 | `WindowSizer` popup origin on the external display |
| 0077 | tabs_api drag input adapter over `EventMonitor` |
| 0077 | `ChromeViewsDelegate` uses content's context factory (Mac file) |
| 0080 | Proxy and cookie settings policy handlers built (components) |
| 0081 | Web app startup utils (`--app` launches) built (Mac parity) |
| 0082 | Standalone trusted vault client/frontend built (Mac parity) |
| 0077 | `RunDragDropLoop` (Mac no-op), `GetMenuSourceTypeForEvent`, `ResizedImageForMaxDimensions` (UIKit) |

## External display (parallel to Views)

iOS 27 default, if the app does not take over the display, is **phone
mirroring**. The shipped 0011 build registered a scene accessory too
weakly (stale registration on a transient view controller; no
`application:configurationForConnectingSceneSession:`) and had no
fallback. UIKit’s own comment on `UIScreen.mirroredScreen` is:
“Moving a UIWindow to this screen will disable mirroring.”

The 0012 takeover fix (in this same push):

- Re-register the iOS 27 accessory when the presenter VC changes;
  log `isAvailable`.
- Implement `configurationForConnectingSceneSession` in
  `MainApplicationDelegate` so UIKit can instantiate
  `DeskBrowserExternalDisplaySceneDelegate`.
- If no external scene session appears but a mirrored / second
  `UIScreen` with non-empty bounds exists, place a `UIWindow` on
  that screen (legacy path) to stop mirroring, then host Chrome
  there with the regular×regular size class.

Simulator regression (iOS 26.5, 2:51 PM ET): the official
`UIWindowSceneSessionRoleExternalDisplayNonInteractive` session still
connects; the phone shows the control surface; the external display
shows the iPad-style tab strip + toolbar. **Not installed on the
phone in this pass** — the device bug is iOS 27.2.1 mirroring, which
the Simulator cannot reproduce. Do not ask for a device test until a
build is signed, installed, and we can verify the takeover ourselves
with a live monitor.

## Milestones

### Milestone 1 — Views widget on the iOS Simulator

**Target:** a `views::Widget` (a `views_examples` subset, or a
minimal window with a Views label/button) rendered on-screen in the
iOS Simulator through a new UIKit-backed platform window. Screenshot
required.

Work:

1. GN flag `enable_ios_desktop_views` (default false) so
   `toolkit_views` can be true on iOS without breaking the existing
   `//ios/chrome` build. Widen the grit assert. Keep `use_aura =
   false` and `enable_library_cdms = false`.
2. Walk the desktop-only GN graph that becomes reachable (web_modal,
   constrained_window, root `views_examples`, watermark, …) and
   either gate it with `!is_ios` or stub it.
3. New `NativeWidgetIOS` (in-process, no Mac app-shim mojo) plus
   `CreateNativeWidget` for iOS.
4. On-screen compositor host: lift
   `test_compositor_host_ios` / `display_ca_layer_tree` so a
   `ui::Compositor` can paint into a `CALayer` inside a `UIWindow`.
   Simulator first; iphoneos afterwards.
5. An `ios_app_bundle` host (`views_examples_ios` or
   `deskbrowser_views_host`) that starts UIKit, `display::Screen`,
   and a Views widget.
6. Screenshot both the phone display and, if attached, the Simulator
   TVOut.

Status at plan time: the GN flag and several all-target gates are
in the tree; `gn gen out/Release-iphonesimulator-views` is still
blocked on desktop-only component asserts (next up:
`components/web_modal`). No Views widget screenshot yet.

**Estimate:** several days to about two weeks.

### Milestone 2 — desktop BrowserView in the Simulator

**Target:** tab strip, toolbar, and a Blink `WebContents` in a Views
`BrowserView` (or `views_content_client` as an intermediate) running
in the Simulator, single-process / jitless.

Work: lift `assert(!is_ios)` in `//chrome` for a slim set of
targets; stub updater/extensions/profile picker; reuse the
already-working content startup flags; host WebContents in the
widget from M1. Full `chrome/browser/ui/views/frame/browser_view`
is the real UI; expect a long dependency walk.

**Estimate:** two to four weeks after M1.

### Milestone 3 — that window on the external display

Host the Milestone 2 widget in the iOS 27 external scene (and the
mirroring-takeover fallback). Simulator TVOut first, then a signed
device IPA once we can see a live monitor ourselves. Input: keyboard
to the external window; phone as pointer / control surface.

**Estimate:** days once M2 works, overlapping the display work
already started.

### Milestone 4 — device IPA, bookmarks bar, app menu, settings WebUI

Sign with the existing entitlements (EVA, increased-memory-limit,
get-task-allow), jitless default, memory cap. Turn on the Views
bookmarks bar and app menu; load `chrome://settings`. Verify on a
real monitor (takeover, not mirroring) before asking David to test.

**Estimate:** one to two weeks after M3.

### Milestone 5 — remaining desktop chrome

Sync, extensions, extra profiles, printing, performance, and
anything still stubbed, only as needed.

## Overall estimate

Several weeks to a first useful “desktop Chrome on the monitor”
device build (M1–M4). That matches the “even if it takes weeks”
brief. The two longest legs are the GN/component garden (M1) and
bringing a slim `//chrome` BrowserView up on iOS (M2). The external
display API is understood; the remaining risk there is iOS 27
mirroring takeover on a real cable, which we will verify ourselves
before asking for a test.

## Standing rules

- Jitless remains the default. JIT stays behind the hidden flag.
- Do not weaken memory entitlements or the heap cap.
- Long builds run detached with a status file and a
  `notify-poke.sh` completion poke.
- Commit to `linux-ios-fast` main, no secrets. Do not amend pushed
  commits.
- Do not ask David to test until something is signed, installed,
  and verified here.
