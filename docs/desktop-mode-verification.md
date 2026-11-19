# Desktop-mode verification: iOS desktop Views BrowserView

Run: 2026-11-19, 10:51–11:00 AM ET. iOS 27.2 Simulator (SIM-UDID), TVOut
1920x1080 @1x, build out/Release-iphonesimulator-views at patch 0116.
Tools: tools/desktop-mode/server.py (local UA echo: request headers plus
Accept-CH/Critical-CH, JS values), cdp.py (DevTools on 127.0.0.1:9333, the
sim build only; it refuses any other owner of the port), batch.sh (fresh
launch per site, TVOut screenshot, JS probe). Raw values are in
tools/desktop-mode/results-2026-11-19.jsonl.

## Checklist

| # | Check | Expected | Observed | Result |
|---|-------|----------|----------|--------|
| 1 | User-Agent header and navigator.userAgent | Mac desktop Chrome | `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/160.0.0.0 Safari/537.36`, no "Mobile" | PASS |
| 2 | navigator.platform | MacIntel | MacIntel | PASS |
| 3 | Sec-CH-UA-Mobile | ?0 | ?0 (every request) | PASS |
| 4 | Sec-CH-UA-Platform / userAgentData.platform | macOS | "macOS" / macOS | PASS |
| 5 | navigator.userAgentData.mobile | false | false (echo + all 6 sites) | PASS |
| 6 | Sec-CH-UA-Form-Factors / formFactors | Desktop | "Desktop" / ["Desktop"] | PASS |
| 7 | Sec-CH-UA-Model | empty | "" | PASS |
| 8 | navigator.maxTouchPoints | 0 | 0 (all pages) | PASS |
| 9 | 'ontouchstart' in window | false | false | PASS |
| 10 | (pointer: fine), (hover: hover), (any-pointer: coarse) | true, true, false | true, true, false | PASS |
| 11 | Viewport width | desktop (window width) | innerWidth = clientWidth = 1912, dpr 1, visualViewport.scale 1 | PASS |
| 12 | Meta viewport ignored | layout width unaffected by `<meta name=viewport content="width=400">` | innerWidth 1912, scale 1 on /echo?vp=400; Wikipedia's width=1120 and others' device-width also ignored (1912) | PASS |
| 13 | whatismybrowser.com | detects desktop macOS Chrome | "Chrome 160 on macOS (Golden Gate)" | PASS |
| 14 | YouTube | www.youtube.com desktop | https://www.youtube.com/, desktop guide/sidebar and masthead | PASS |
| 15 | Google | www.google.com desktop | https://www.google.com/ home and /search?q=chromium desktop SERP, no meta viewport (desktop markup) | PASS |
| 16 | Wikipedia | en.wikipedia.org (not en.m.) | https://en.wikipedia.org/wiki/Main_Page, Vector 2022 with Appearance panel | PASS |
| 17 | Reddit | www.reddit.com desktop | https://www.reddit.com/, desktop chrome; served reddit's "Prove your humanity" reCAPTCHA wall (bot check, not a mobile page) | PASS (desktop) / content gated |
| 18 | X | x.com desktop | https://x.com/, desktop two-column login with "Scan to get the app" QR | PASS |
| 19 | No m./mobile redirects | none | final URLs: www.whatismybrowser.com, www.youtube.com, en.wikipedia.org, www.reddit.com, x.com, www.google.com | PASS |

## Notes (not failures)

- Brands are `Not)A;Brand` + `Chromium` 160: this is an unbranded Chromium
  build, so there is no "Google Chrome" brand. A branded build would add it.
- UA-CH platformVersion reports 27.2.0 (the host OS version). It is a
  plausible macOS version string but is the iOS runtime's number.
- Reddit's bot wall is likely the fresh profile, no cookies and a
  datacenter/sim network; it is a desktop page.

## Re-run on HEAD 06fbcff (19 Nov 2026, 11:41–11:48 AM ET)

Re-run after the trackpad/focus patches 0117–0121, adding the local UA echo
page to the batch. All sites PASS again: Mac UA (Intel Mac OS X 10_15_7,
no "Mobile"), Sec-CH-UA-Mobile ?0, Sec-CH-UA-Platform "macOS", form factors
"Desktop", userAgentData.mobile false, maxTouchPoints 0, no ontouchstart,
pointer fine + hover, innerWidth = clientWidth = 1912, visualViewport scale 1,
and no m./mobile redirects (www.youtube.com, en.wikipedia.org, www.reddit.com,
x.com, www.google.com). Reddit's desktop feed loaded this time (no captcha wall).
Raw probe output: tools/desktop-mode/results-2026-11-19-rerun-1144.jsonl.

## Re-run 2026-11-19, 1:15–1:21 PM ET (patches through 0130)

After the context-menu, input, diagnostics-trim, audio and shutdown changes.
batch.sh now takes the ALIVE/DEAD line from site.sh (the TVOut re-plug notice
could come first and made the 11:44 run reuse a stale X screenshot) and takes
a fresh TVOut screenshot after each probe. Raw values:
tools/desktop-mode/results-2026-11-19-rerun-1315.jsonl.

| Page | UA Mac, no Mobile | platform | uaData.mobile / platform | maxTouchPoints / ontouchstart | pointer fine / hover | innerWidth = clientWidth, dpr, scale | Final URL | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| UA echo | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | http://127.0.0.1:8765/ | PASS |
| echo, meta viewport width=400 | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 (meta ignored) | /echo?vp=400 | PASS |
| whatismybrowser | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | www.whatismybrowser.com ("Chrome 160 on macOS") | PASS |
| YouTube | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | www.youtube.com | PASS |
| Wikipedia | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | en.wikipedia.org | PASS |
| Reddit | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | www.reddit.com (desktop feed this time) | PASS |
| X | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | x.com (fresh desktop login screenshot) | PASS |
| Google | yes | MacIntel | false / macOS | 0 / false | true / true | 1912, 1, 1 | www.google.com/search?q=chromium | PASS |

Request headers on the echo server: Sec-CH-UA-Mobile ?0, Sec-CH-UA-Platform
"macOS", Sec-CH-UA-Form-Factors "Desktop", Sec-CH-UA-Model "", Mac UA.
No m./mobile redirects. Screenshots: views-m2-real/desktop-mode/rerun-1315/
(contact-sheet.png plus one per page). Result: all PASS.
