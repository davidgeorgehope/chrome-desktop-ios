# Desktop-mode verification: iOS desktop Views BrowserView

Run: 2026-11-19, 10:51–11:00 AM ET. iOS 27.2 Simulator (DE1E2D59…), TVOut
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
