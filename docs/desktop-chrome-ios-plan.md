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
| 0083 | Feedback-disabled dialog | not shown (histogram still recorded) | build `feedback_disabled_dialog` |
| 0083 | chrome://policy custom command line | not reported | `ScopedInitialCommandLine` on iOS |
| 0083 | Settings "System" strings, delete-profile on sign out | skipped (single profile, no System page) | System handler / profile_helper |
| 0083 | Picture-in-picture auto occlusion | stub helper (Android's) | widget occlusion helper |
| 0083 | System notifications bridge | none, message center only (`CanHandleType` false) | UNUserNotificationCenter bridge |
| 0083 | Version updater | basic (no update UI, like Linux) | App Store update check |
| 0084 | Device signals: agent (CrowdStrike), certificate, desktop OS, file system collectors; system signals host | not collected (profile signals only) | iOS device signals collectors |
| 0084 | Device trust browser signals decorator | not added | build `browser_signals_decorator` |
| 0084 | Managed-profile-required interstitial "open in managed profile" | falls back to the plain interstitial | managed profile creation |
| 0084 | Browser launch event reporting (browser and profile) | none (as on Android) | `browser_launch_event_uploader_desktop` |
| 0086 | Cast remoting (tab mirroring / remote playback permission) | skipped, `ENABLE_MEDIA_REMOTING` is off on iOS | media remoting on iOS |
| 0086 | Security settings bundle toast, multistep filter observer, walletable pass detection | not created | build those targets |
| 0086 | Enterprise referrer chain from Safe Browsing nav observer | empty chain | Safe Browsing on iOS Views |
| 0086 | Deprecated Chrome Apps dialogs | not shown | build `web_apps` deprecated dialogs |
| 0086 | Password keychain-error relaunch bubble, biometric auth bubbles | not shown | relaunch view / iOS biometrics |
| 0086 | History sync opt-in dialog, managed user notice dialog, signin intercept FRE dialog | `NOTIMPLEMENTED()`, flow skipped | build HistorySyncOptinUI / ManagedUserProfileNoticeUI |
| 0086 | Managed-profile disclaimer in DICE interception and history sync | skipped (managed accounts skip history sync opt-in) | `ProfileManagementDisclaimerService` |
| 0086 | Structured metrics recorder | not created | build `chrome_structured_metrics_delegate` |
| 0086 | UI DevTools DOM/overlay agents | server runs with tracing only | `DOMAgentIOS` / `OverlayAgentIOS` |
| 0087 | Session restore infobar controller member | removed from `BrowserWindowFeatures` on iOS | build `session_restore_infobar` |
| 0087 | Update metrics provider | not registered (no updater) | n/a |
| 0087 | CBCM remote commands + invalidator | not started | build `cbcm_remote_commands_factory` |
| 0087 | Removable storage list (imageWriterPrivate) | always empty | n/a on iOS |
| 0091 | Enterprise client certificates: unexportable (Secure Enclave) keys | software keys only (no keychain access group) | keychain access group entitlement |
| 0092 | Supervised user: locally-parent-approved extensions migration pref | registered on iOS Views like Win/Mac/Linux (pref was declared but unregistered) | — |
| 0093 | Segmentation home-modules card registry (iOS magic stack) | Create() returns nullptr on iOS Views like desktop | — (desktop has no magic stack) |
| 0094 | Accelerator long-form Cmd modifier text | ported: iOS uses the Mac "Command" string (was NOTREACHED) | — |
| 0095 | ui::ImageModel vector icon rasterize | ported: ThemedVectorIcon path enabled on iOS Views (was NOTREACHED on iOS) | — |
| 0096 | OS-level geolocation permission manager | ported: created at PreMainMessageLoopRun via SystemGeolocationSourceApple, like Mac (new browser_process_platform_part_ios.mm) | — |
| 0097 | Instant extended API (WebUI NTP instant process) | enabled on iOS Views like desktop (was false for all iOS) | — |
| 0098 | Native display::Screen for Chrome on iOS Views | ported: ChromeBrowserMainExtraPartsViews::PreCreateThreads installs display::ScopedNativeScreen (ScreenIOS), like ChromeBrowserMainExtraPartsMac | — |
| 0099 | Resource scale factors | ported: iOS Views supports 100P+200P like desktop/Mac (was only the panel DSF, 300P) | 300P pak if wanted for the 3x panel |
| 0100 | Browser main loop on iOS | ported: ChromeMainDelegate::RunProcess initializes and leaks a BrowserMainRunner and returns to UIApplicationMain (as content_shell iOS does) | — |
| 0101 | Feature engagement on-device event storage (iOS mobile path) | cut: iOS Views uses desktop profile-only event storage | — |
| 0102 | NativeWidgetIOS scene placement | ported: widgets created before any UIScene connects are re-homed on UISceneWillConnect/DidActivate (preferring the external scene); top-level windows fill large screens | — |
| 0103 | iOS 27 external display scene | ported: phone scene delegate registers UISceneAccessory.externalNonInteractive on its stable root VC (as 0012/0024 did for iOS Chrome); TVOut scene now connects | — |
| 0104 | Widget resize on scene move | ported: MoveToPreferredScene goes through SetBounds so RootView/BrowserView get OnNativeWidgetSizeChanged at the new screen size | — |
| 0105 | ScreenIos displays, cursor, idle | ported: one display::Display per UIScreen (external = primary at origin, panel to its right), GetDisplayNearestWindow/View by UIScreen, scene connect/disconnect refresh; stubs: cursor point = primary center, CalculateIdleTime 0 (no iOS idle timer; enterprise idle timeout never fires) | pointer-based cursor tracking; idle from last UIEvent |
| 0106 | Child processes / JIT / PA quarantine | cut: iOS Views host defaults to --single-process --in-process-gpu --js-flags=--jitless and disables NetTaskScheduler, NetworkServiceTaskScheduler, PartitionAllocSchedulerLoopQuarantine (no BrowserEngineKit extensions bundled; quarantine OOM-traps on a normal free) | BrowserEngineKit renderer/GPU extensions; investigate quarantine sizing |
| 0107 | NativeWidgetIOS diagnostics | diag: one-shot CALayer/UIView tree dump 8 s after a TYPE_WINDOW moves scenes, and a widget name/type/contents NSLog on Show, used to find the stray bubbles (BubbleDialogModelHost 334x157). Temporary; trim once the stray widgets are gone. |
| 0108 | Widget ownership (GetAllOwnedWidgets) | port: NativeWidgetIOS tracks its owning widget (InitParams::parent, ReparentNativeViewImpl with cycle check; cleared when the parent dies). GetAllOwnedWidgets returns transitively owned widgets excluding itself; GetAllChildWidgets adds itself. Fixes infinite recursion in BrowserView::GetAccessibleWindowTitle on every navigation (UI froze at "Loading…"; earlier seen as the PA quarantine OOM). Fills the ReparentNativeViewImpl stub. |
| 0109 | GPU presenter main-queue UAF | fix: ImageTransportSurfaceOverlayMacEGL host-attach block captured raw `this`; surfaces destroyed before the main-queue hop (navigation recreates frame sinks) caused SEGV on 0xcdcd... Now uses a RefCountedThreadSafe guard with a lock, cleared in the destructor. |
| 0110 | System UI font | port: PlatformFontIOS::GetCTFont asks UIKit for systemFontOfSize:weight: (plus italic trait) when the font name is dot-prefixed (".SFUI-Regular"), which fontWithName: maps to Times New Roman on iOS 13+. Views UI now renders in SF. ENABLE_IOS_DESKTOP_VIEWS only. |
| 0111 | In-process WebContents compositing | port: with --in-process-gpu/--single-process the presenter parents each surface root CALayer directly on its CALayerFrameSinkProvider (RWHV) layer instead of handing it to a BELayerHierarchy nobody hosts, and inserts it at index 0 so native subviews stay on top. First real Blink page (example.com) on TVOut. |
| 0112 | On-device model service | cut: content/utility/services.cc RunOnDeviceModel returns null on iOS Views (in-process utilities never run the on-device-model pre-sandbox hook; CHECK fired ~3 min after launch). Callers see a disconnect = on-device AI unavailable. |
| 0113 | Web contents placement diagnostics | diag: NativeViewHostIOS::ShowWidget logs frame changes (view class, superview, z-index), and the GPU presenter logs each sink superview chain (class, frame, clips, hidden). Used to find why the page covers the whole TVOut window. Temporary. |
| 0114 | NativeViewHost subview sizing | fix: DeskBrowserViewsContentView layoutSubviews stretched every sublayer, including backing layers of native subviews, so the WebContents UIScrollView covered the whole window. It now only stretches non-UIView (compositor) layers. Page sits in the contents area under the real tab strip and toolbar. |
| 0115 | Single-process infobar | cut: chrome/browser/ui/startup/bad_flags_prompt.cc leaves switches::kSingleProcess out of kBadFlags on iOS Views (the host always injects it; not a user flag). Infobar gone; web area 1912x984. |
| 0116 | PA quarantine back on | revert of the 0106 workaround: PartitionAllocSchedulerLoopQuarantine is no longer disabled by the iOS Views host. Its OOM trap was the GetAllOwnedWidgets recursion fixed in 0108. |
| 0117 | NativeWidgetIOS trackpad input + focus | static DispatchTrackpadMouseEvent / DispatchTrackpadKeyEvent entry points; NativeWidgetIOS is a FocusChangeListener and resigns the window first responder (endEditing) when Views focus moves to a non-NativeViewHost view, like NativeWidgetMacNSWindowHost::OnDidChangeFocus. |
| 0118 | RenderWidgetUIView focus gate | under ENABLE_IOS_DESKTOP_VIEWS, didMoveToWindow only re-grabs first responder if the view already had focus; Views FocusManager owns focus. Fixes omnibox focus being stolen back by ContentsWebView after a click. |
| 0119 | Phone trackpad for the Views BrowserView | ChromeViewsIOSTrackpadView on the phone scene: 1-finger pan moves a cursor overlay on the TVOut scene, tap = left click, two-finger tap = right click, two-finger pan = scroll; clicks/scroll go to Blink (RenderWidgetUIView inject) or Views (NativeWidgetIOS); UIKeyInput + presses -> ui::KeyEvent. Keyboard button toggles soft keyboard. Omnibox navigation verified. |
| 0120 | NativeWidgetIOS CloseNow notifies destroying | Widget::CloseNow (StatusBubbleViews::DestroyPopup) went straight to NativeWidgetIOS::CloseNow, which sent OnNativeWidgetDestroyed without OnNativeWidgetDestroying -> CHECK(widget_destroying_handled_). CloseNow now sends destroying once. Hit when the trackpad cursor hovered links. |
| 0121 | Trackpad scroll diagnostics | logs two-finger scroll begin/end with delta and hit view class (debug; trimmed with the other trackpad logs). Scroll verified: Wikipedia scrollY 0 -> 570 -> 0. |
| 0122 | iOS Views audio: Playback-first AVAudioSession | under ENABLE_IOS_DESKTOP_VIEWS AudioSessionManagerIOS starts in AVAudioSessionCategoryPlayback (MixWithOthers) instead of PlayAndRecord, and switches to PlayAndRecord in EnsureRecordingCategory() when AudioManagerIOS creates an input stream. Fixes AURemoteIO::Initialize "RPC timeout. Apparently deadlocked" abort on YouTube playback in the Simulator. Same AudioManagerIOS/RemoteIO path as iOS Chrome; no Mac AUHAL device code. |
| 0123 | Mic/camera usage strings | chrome_views_ios Info.plist adds NSMicrophoneUsageDescription and NSCameraUsageDescription (as content_shell does) so getUserMedia can prompt instead of TCC-killing the app. |
| 0124 | Cursor lookup and right-button web injection | ScreenIos now tracks the phone cursor and resolves visible interactive windows by display coordinates and window level; overlays ignored. Trackpad routes left/right/middle web clicks to Blink. DOM right-button/contextmenu verified; Chrome context menu delegate is still null (next fix). Phone audit confirms no Views widgets on LCD. |
| 0125 | Views menus on iOS | NativeWidgetIOS returns a no-op GestureRecognizer (Mac stub, now built for iOS) so MenuHost::ShowMenuHost does not SEGV; only parentless TYPE_WINDOW widgets are maximized on desktop-sized scenes (menus/bubbles were full-screen); OnWidgetInitDone sizes RootView to Init bounds (menus were blank); GetNativeWidgetForNativeView walks superviews like Mac/Aura. App menu verified on TVOut. |
| 0126 | Web context menu | iOS desktop Views builds the Views ChromeWebContentsViewDelegate and RenderViewContextMenuViews without Aura (screen point from WebContentsViewIOS::GetContainerBounds, no Aura bookmark drag handler); Apple spelling menu branch for iOS. Right-click on a web page shows the Chrome context menu. |
| 0127 | Pointer input only to the active page | RenderWidgetHostViewIOS::CanAcceptDesktopPointerInput (showing, host not hidden, not prerendering); RenderWidgetUIView refuses injected mouse/wheel otherwise and the trackpad searches for the front-most accepting web view. Fixes NOTREACHED in RenderWidgetHostViewBase::ProcessMouseEvent after omnibox prerender. |
| 0128 | Trim bring-up diagnostics | Removes per-frame/tree-dump logs (viz ScheduleOverlays/PresentFrame/DoFinishSwapBuffers/ProcessForOverlays, UpdateCALayerTree, presenter Present/ScheduleCALayer/sink chain, CommitPresentedFrameToCA + CA dumps, NativeWidgetIOS layer/view dumps and placement, NativeViewHost frames, trackpad key/scroll/text/responder/window audit). Keeps one-line lifecycle logs (scene willConnect, attached compositor, No CALayer host, trackpad attached/click/cursor) used by the test scripts. Functional code (empty-candidate fallback, CATransaction flush, delayed ScheduleDraw) kept. Startup log: 7 lines. |
| 0129 | Clean shutdown on SIGTERM | BrowserProcessImpl::EndSession waits for pref/Local State rundown on iOS like Mac (was NOTIMPLEMENTED, nothing flushed). Verified: Preferences + Local State written at kill time, stability.exited_cleanly=true. |
| — | Desktop-mode verification | verified: Mac desktop UA, Sec-CH-UA-Mobile ?0, platform macOS, userAgentData.mobile false, maxTouchPoints 0, desktop viewport with meta viewport ignored, no m. redirects on whatismybrowser/YouTube/Google/Wikipedia/Reddit/X. See docs/desktop-mode-verification.md. |

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
| 0083 | Bookmark clipboard (copy/paste bookmarks) via ui::Clipboard iOS |
| 0083 | `HandleAppExitingForPlatform` (closes remaining widgets) |
| 0083 | `GetDirectLaunchUrlScheme` (empty: no google-chrome:// scheme) |
| 0083 | `OpaqueBrowserFrameView` implementation linked into the iOS frame factory |
| 0084 | SaaS usage reporting (Android/desktop shared sources) built |
| 0084 | Enterprise idle timeout dialog manager + Views idle dialog and enterprise startup dialog built |
| 0085 | `Widget::CloseAllWidgets` for NativeWidgetIOS (closes every top-level widget window) |
| 0085 | Built (Mac/Android parity): autofill cross-tab copy/paste tracker, initial account bookmark deduplicator, desktop extension install UI, supervised user web content handler / YouTube verification page, enterprise connectors common + realtime reporting client |
| 0087 | guest_contents enabled (WebUI browser iframe guests), Controlled Frame API provider, web contents menu helper, IWA key distribution policy, background mode manager (Mac file) built |
| 0087 | iOS chrome://management resources come from //chrome (drops the duplicate components copy) |
| 0088 | `base::AtExitManager` created in `main` (content does not create one on iOS) |
| 0089 | Locale paks bundled as `en.lproj`, `en_GB.lproj`, ... (Apple naming, what `ResourceBundle` iOS looks up) |
| 0089 | Content/website settings registry: iOS Views registers the Mac platform list (file system access, etc.) |
| 0090 | Message center + Chrome notifications enabled (Mac parity fallback for web notifications); `MessagePopupView::GetOpacity` reads the UIWindow alpha; `IsFullScreenMode` (false: no foreign full-screen app on iOS) |
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
