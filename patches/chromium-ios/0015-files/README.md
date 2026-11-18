Fix grit DuplicateKey IDS_SAD_TAB_RELOAD_INCOGNITO when
enable_ios_desktop_views makes toolkit_views true on iOS.

The desktop "Ctrl-Shift-N" string was under
`not is_macosx and toolkit_views`, which now overlaps
`is_android or is_ios`. Restrict the desktop branch with
`and not is_ios`. Apply after 0014.
