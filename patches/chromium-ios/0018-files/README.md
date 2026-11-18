Pack Blink permission-element strings into iOS Chrome paks.

0012's page-load crash (Chromium-2026-11-18-155911.ips, 3:59:11 PM ET)
was a CHECK in ui::ResourceBundle::GetLocalizedStringImpl. Blink's
HTMLMediaCaptureElementBase::UpdateAppearance calls
GetLocale().QueryString() for IDS_PERMISSION_REQUEST_CAMERA /
MICROPHONE (and the generated per-language IDs) when a page contains
a stable <camera>, <microphone>, or <usermedia> element.

Desktop chrome_repack_locales and chrome_paks already include
permission_element_strings and permission_element_generated_strings.
iOS packed blink_strings_en-US.pak into resources.pak but omitted
both permission-element paks. The 661b06eb known-good no-JIT IPA
has the same hole (the distinctive strings "Use microphone and
camera" / "Precise location allowed" are absent from resources.pak
and en.lproj/locale.pak), so that baseline will also abort on the
same element.

This adds:
- permission_element_generated_strings.pak and
  permission_element_strings_en-US.pak to the iOS resources.pak
  (alongside blink_strings_en-US.pak).
- permission_element_strings_ to ios_chrome_repack_locales so
  non-English locale.paks get the untranslated IDs too.

Apply `../0018-ios-permission-element-strings-paks.patch` after 0017.
