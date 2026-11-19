Fix Return-to-submit in the omnibox when typing through the phone
trackpad / forwarded hardware keys.

0023 forwarded keys with insertText: and treated Return as
insertText:@"\n". On the composebox UITextView that inserted a visual
second row and skipped textInputShouldReturn. Even after calling the
omnibox keyboard-action path, acceptInput no-op'd because programmatic
insertText: often skips shouldChangeTextInRange, so
processingUserEvent stays NO, the text model never updates, and
currentMatch has no valid destination_url.

This follow-up:

- Types printable characters with insertTextWhileEditing: when the
  focused field implements it, so the omnibox delegate updates the
  text model and autocomplete.
- On Return / KeypadEnter, walks the responder chain and calls
  performKeyboardAction:kReturnKey (enum value 4) instead of
  inserting a newline. Falls back to insertText:@"\n" if that action
  is not available.

Verified on the iOS 27.2 Simulator (iPhone Duo, TVOut 1920×1080):
typing en.wikipedia.org/wiki/United_States filled the omnibox and
autocomplete suggestions; Return logged "omnibox accept via
OmniboxTextViewIOS" and navigated (URL bar showed en.wikipedia.org,
then a local http URL after a second submit). Two-finger scroll on
the trackpad injected wheel events into the RenderWidget
("trackpad two-finger scroll began", wheel phase=1). Web content on
the official external display stayed a gray loading surface in this
sim (stop button remained), so a visual before/after scroll on a
painted long page could not be confirmed here. Phone-side page
render was previously verified on 0022.

Apply after 0023. Device IPA: Views flag off, jitless default. Does
not include the uncommitted Views M1 (0021) work.
