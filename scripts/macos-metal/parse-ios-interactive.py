#!/usr/bin/env python3
"""Summarize one iOS interactive run: parse-ios-interactive.py SERIAL [SESSION] [MEMLOG]"""
import re, sys
def rd(p):
    try: return open(p, 'rb').read().decode('utf-8', 'replace').replace('\r', '')
    except Exception: return ''
s = rd(sys.argv[1]); sess = rd(sys.argv[2]) if len(sys.argv) > 2 else ''; mem = rd(sys.argv[3]) if len(sys.argv) > 3 else ''
def up(tag):
    m = re.search(r'===%s===[^\n]*?\bup(?:time)?=([0-9.]+)' % tag, s)
    return float(m.group(1)) if m else None
def kv(tag, key):
    m = re.search(r'===%s===[^\n]*?\b%s=([^\s]+)' % (tag, key), s)
    return m.group(1) if m else 'na'
start = up('FIREFOX_START') or up('CHROMIUM_START')
br = 'firefox' if up('FIREFOX_START') else 'chromium'
la = up('INTERACTIVE_LAUNCH'); ready = up('DESKTOP_READY')
wn = up('INTERACTIVE_WARM_NAV'); wl = up('INTERACTIVE_WARM_LAUNCH')
st = None
for line in (sess + mem).split('\n'):
    pass
stats = re.findall(r'===JIT_SHARED_STATS===[^\n]*', sess)
ins = ev = mx = acc = 'na'
if stats:
    last = stats[-1]
    g = lambda k: (re.search(r'\b%s=(\d+)' % k, last) or [None, 'na'])[1]
    ins, ev, acc, mx = g('insertions'), g('evictions'), g('accounted'), g('max')
rss = [int(x) for x in re.findall(r'^\s*(\d+)\s+\d+\s+\S*Kernarium\.app/Kernarium', mem, re.M)]
rss += [int(x) for x in re.findall(r'^\s*\d+\s+(\d+)\s+\S*Kernarium\.app/Kernarium', mem, re.M)]
f = lambda v: 'na' if v is None else '%.2f' % v
print('browser=%s ready_up=%s start_up=%s launch_up=%s cold_from_start=%s first_paint_ms=%s scroll_fps=%s frames=%s p95=%s input=%s key_ms=%s click_ms=%s key_n=%s click_n=%s warm_dup=%s warm_nav_ms=%s shared_ins=%s shared_evict=%s shared_max=%s peak_rss_mib=%s' % (
    br, f(ready), f(start), f(la), f(la - start if la and start else None), kv('INTERACTIVE_LAUNCH', 'first_paint_ms'),
    kv('INTERACTIVE_SCROLL', 'fps'), kv('INTERACTIVE_SCROLL', 'frames'), kv('INTERACTIVE_SCROLL', 'p95_frame_ms'),
    kv('INTERACTIVE_INPUT', 'why'), kv('INTERACTIVE_INPUT', 'key_raf_ms'), kv('INTERACTIVE_INPUT', 'click_raf_ms'),
    kv('INTERACTIVE_INPUT', 'key_n'), kv('INTERACTIVE_INPUT', 'click_n'), f(wl - wn if wl and wn else None),
    kv('INTERACTIVE_WARM_LAUNCH', 'nav_ms'), ins, ev, mx, (max(rss) // 1024 if rss else 'na')))
