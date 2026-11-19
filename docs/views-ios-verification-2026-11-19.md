# iOS desktop Views: interaction checks, 2026-11-19

iOS 27.2 Simulator, TVOut 1920x1080, phone scene as trackpad. Helpers in tools/ios-views-trackpad/.

| Area | Check | Result |
| --- | --- | --- |
| Right-click | Two-finger tap on a page opens Chrome's web context menu at the cursor (Back/Forward/Reload/Save As/Print/Cast/.../View Page Source/Inspect) | PASS (0126, 0127) |
| | Escape closes the menu | PASS (0130) |
| | Click outside closes the menu (capture routing) | PASS (0130) |
| | Down highlights Reload, Return activates it (page reloaded: window marker cleared) | PASS (0130) |
| | Click on disabled Forward leaves the menu open | PASS (expected desktop behaviour) |
| | Accelerator labels show keys (Ctrl+R, Ctrl+U, Alt+Shift+R) | PASS (0131) |
| | Mouse click on an enabled item | not separately shown (cursor positioning is coarse); the keyboard path and captured clicks are |
| App menu | Opens sized 418x716 with all entries | PASS (0125) |
| Stray phone widgets | Phone scene shows only the trackpad, also with a menu open on TVOut; window audit found no Views UIWindow on the phone scene | PASS (0124 audit, since removed in 0128) |
| Window under cursor | Screen::GetWindowAtScreenPoint over an open menu returns the menu window (frame 889,500 408x398); outside it the browser window; after Escape the browser window; IsWindowUnderCursor true for each; GetCursorScreenPoint equals the trackpad cursor | PASS (0124; temporary log, not committed) |
| Mic | getUserMedia on http://127.0.0.1 (secure context): live track "Default"/MicrophoneBuiltIn, 48 kHz mono, RMS 0.10 (signal present); MediaRecorder 3 s = 41,577 bytes audio/webm;codecs=opus; session stays output-only until input, then RemoteIO input starts with no timeout; app alive | PASS (0122, 0123) |
| Shutdown | SIGTERM flushes Preferences and Local State; stability.exited_cleanly true | PASS (0129) |
| Diagnostics | Startup prints 7 [DeskBrowser] lines (was hundreds) | PASS (0128) |

The mic run used --use-fake-ui-for-media-stream to auto-accept Chrome's own
permission prompt and `simctl privacy grant microphone` for the simulator
app; the audio device was real (the Mac's input via the simulator).

## Remaining NOTIMPLEMENTED lines (current build)

| Message | Status |
| --- | --- |
| actor::ToolRequest::GetToolDefinition | Upstream fallback, logged once on every platform: ChangePasswordToolRequest and ExecuteJsToolRequest have no schema yet upstream. Not an iOS stub; left alone. |
| SimpleMenuModel separator types | Same as upstream Mac (non-Aura): spacing separators render as normal. |
| ViewAccessibility::SetPopupFocusOverride | Accessibility platform delegate not ported to iOS Views (Mac has one). VoiceOver for desktop Views is future work. |
| RenderWidgetHostViewBase::GetKeyboardLayoutMap | navigator.keyboard.getLayoutMap() returns empty; Mac implements it. Low priority. |
| Fixed in this pass | ScreenIos::GetCursorScreenPoint (0124), BrowserProcessImpl::EndSession (0129), MenuPreTargetHandlerIOS (0130). |
