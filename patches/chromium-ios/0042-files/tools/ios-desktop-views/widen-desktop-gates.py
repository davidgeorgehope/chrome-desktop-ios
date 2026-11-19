#!/usr/bin/env python3
"""Widen pure desktop-platform preprocessor gates for desktop Views on iOS.

Finds `#if`/`#elif` whose condition is only an OR-list of BUILDFLAG(IS_<platform>)
terms that includes IS_MAC plus IS_WIN or IS_LINUX (a "desktop" list) and appends
`|| BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)`. Mac-only or negated gates are left alone.
usage: widen-desktop-gates.py [--dry] DIR...   (run from chromium src)
"""
import os, re, sys
dry = '--dry' in sys.argv
INC = '#include "build/ios_buildflags.h"'
TERM = re.compile(r'^\s*(BUILDFLAG\(IS_(WIN|MAC|LINUX|CHROMEOS|FUCHSIA|ANDROID|DESKTOP_ANDROID)\))\s*$')
SKIP = ('/android/', '/ash/', '/chromeos/', '/win/', '/linux/', '/fuchsia/')
def cond_ok(c):
    c = re.sub(r'\s+', ' ', c.replace('\\\n', ' ')).strip()
    while c.startswith('(') and c.endswith(')'):
        inner = c[1:-1]
        if inner.count('(') == inner.count(')'): c = inner.strip()
        else: break
    parts = c.split('||')
    plats = []
    for p in parts:
        p = p.strip().strip('()').strip() if p.strip().startswith('(') and p.strip().count('(') > p.strip().count(')') else p.strip()
        m = TERM.match(p)
        if not m: return False
        plats.append(m.group(2))
    return 'MAC' in plats and ('WIN' in plats or 'LINUX' in plats)
total = 0
for root in [a for a in sys.argv[1:] if a != '--dry']:
    for r, d, fs in os.walk(root):
        if any(s in r + '/' for s in SKIP): continue
        for f in fs:
            if not f.endswith(('.cc', '.h', '.mm')) or 'test' in f: continue
            p = os.path.join(r, f)
            s = open(p).read()
            if 'IS_MAC' not in s: continue
            lines = s.split('\n'); out = []; i = 0; n = 0
            while i < len(lines):
                l = lines[i]
                m = re.match(r'^#\s*(if|elif)\s+(.*)$', l)
                if m:
                    blk = [l]
                    while blk[-1].endswith('\\') and i + 1 < len(lines):
                        i += 1; blk.append(lines[i])
                    cond = '\n'.join(blk)[len(re.match(r'^#\s*(if|elif)\s+', l).group(0)):]
                    if cond_ok(cond) and 'ENABLE_IOS_DESKTOP_VIEWS' not in cond:
                        blk[-1] = blk[-1] + ' || \\'
                        blk.append('    BUILDFLAG(ENABLE_IOS_DESKTOP_VIEWS)')
                        n += 1
                    out.extend(blk)
                else:
                    out.append(l)
                i += 1
            if n:
                s2 = '\n'.join(out)
                if INC not in s2:
                    if '#include "build/build_config.h"\n' in s2:
                        s2 = s2.replace('#include "build/build_config.h"\n', '#include "build/build_config.h"\n' + INC + '\n', 1)
                    else:
                        mm = re.search(r'^#include .*\n', s2, re.M)
                        s2 = s2[:mm.end()] + INC + '\n' + s2[mm.end():]
                if not dry: open(p, 'w').write(s2)
                total += n
                print(n, p)
print('TOTAL', total, file=sys.stderr)
