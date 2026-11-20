iOS Views: mouse reaches the whole monitor

Apply after 0140. Used by the desktop Views app (chrome_views_ios,
out/Release-iphoneos-views and the simulator). The ios/chrome Chromium.app
device build keeps enable_ios_desktop_views off.

What this patch does
--------------------
On a phone the mouse could only reach part of the monitor. When GameController
reports nothing for the mouse, the cursor follows the iOS pointer over the
phone trackpad. That pointer is absolute and stops at the phone's edges, so
its deltas at the finger trackpad gain (2.5) could only cover the phone's size
times 2.5 (about 980 of 1920 points across on a 393-point-wide phone), offset
wherever the two pointers started. GCMouse and the iOS pointer could also take
turns moving the cursor, since UIKit was ignored only for one second after
each GameController event.

- All cursor motion is relative and goes through one clamp to the whole
  external display in desktop DIPs (its UIKit points, the rect ScreenIos
  reports for the primary display the browser window fills): x in
  [0, width - 1], y in [0, height - 1]. Hover, finger pans, hardware-mouse
  motion and drags share it.
- Once a connected GCMouse reports motion, UIKit's pointer (hover, indirect
  clicks, scroll events) is ignored until the last mouse disconnects, so the
  two paths never fight.
- Phone-pointer fallback: the gain is raised so phone-sized travel spans the
  whole monitor on both axes, and resting the iOS pointer on a phone edge pins
  the cursor to the same monitor edge. Mouse drags arriving as indirect-pointer
  pans use the same gain; finger pans keep 2.5.
- The geometry lives in views_trackpad_ios_geometry.h (no UIKit), with
  compile-time checks in views_trackpad_ios_geometry_checks.cc (a 1920x1080
  monitor at scale 1 against a 393x852 phone); a regression fails the build.
- Logs the external bounds, scale and trackpad size at attach, and which mouse
  path is in use.

Simulator check (1920x1080 TVOut): finger pans reach {1919, 540},
{1919, 1079}, {0, 1079} and {0, 0}; move and tap still click a page input.
Swapping the monitor for phone-sized bounds makes 8 of the compile-time
checks fail. A physical mouse is not available in the simulator.

Replace the listed files with the copies in this directory.
