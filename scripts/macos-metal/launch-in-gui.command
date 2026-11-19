#!/bin/bash
# Open this from the Mac GUI so uml-darwin can create an AppKit window.
# Uses a pty (script(1)) so guest serial is line-buffered into session.log.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
NOTES=$HOME/linux-ios-bakeoff/notes/macos-metal-desktop
export UML_GPU_DISPLAY=native
cd "$NOTES"
# script(1) allocates a pty; -q quiets the header on modern macOS.
exec /usr/bin/script -q "$NOTES/session.log" "$NOTES/launch-uml-darwin-desktop.sh"
