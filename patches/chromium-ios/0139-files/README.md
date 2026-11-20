iOS Views: send Enter and page keys as real key events

Apply after 0138. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator). The ios/chrome Chromium.app
device build keeps enable_ios_desktop_views off.

What this patch does
--------------------
Return on the phone trackpad (hardware keyboard or the on-screen keyboard) reached web content only as typed text: UIKeyInput insertText:@"\n" went to RenderWidgetUIView insertText:, which commits it through ImeCommitText. Pages never got a keydown Enter, so Google's search box (a textarea that submits on keydown Enter) got a newline instead of searching. Arrows, Escape and paging keys never reached pages at all.

- RenderWidgetUIView gains deskBrowserInjectKeyWithWindowsKeyCode:domCode:domKey:text:modifiers:, which sends a NativeWebKeyboardEvent kKeyDown (Blink dispatches keydown and keypress) or kRawKeyDown for keys without text, then kKeyUp, with windows key code, DOM code and DOM key set. Blink's keypress default handling still inserts a newline in a textarea and submits a single-line input's form.
- The trackpad maps hardware Return, keypad Enter, Tab, Escape, arrows, Page Up/Down, Home, End and Forward Delete to that call for the clicked web view, with Shift/Control/Alt/Meta modifiers.
- Text from the on-screen keyboard is split: Return and Tab become key events, everything else stays text.

Simulator check: hardware Return in a textarea gives keydown/keypress/keyup Enter (code Enter, keyCode 13) and a newline; hardware Return in a form input submits the form; Google search submits on Return (URL becomes /search?q=...); on-screen keyboard Return submits a form.

Replace the listed files with the copies in this directory.
