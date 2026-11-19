#!/usr/bin/env python3
"""Make a component follow desktop code paths under enable_ios_desktop_views.

C++: BUILDFLAG(IS_IOS) -> BUILDFLAG(IOS_MOBILE_UI) (+ build/ios_buildflags.h).
GN:  is_ios -> (is_ios && !enable_ios_desktop_views) (+ ui.gni import).
Files under an ios/ subdirectory are left alone (they only build for mobile UI).
usage: desktopize.py [--dry] DIR_OR_FILE...   (run from chromium src)
"""
import os, re, sys
dry='--dry' in sys.argv
INC='#include "build/ios_buildflags.h"'
def restore_positive_lists(s):
    """Keep IS_IOS where the condition already means desktop: pure OR-lists that
    include IS_MAC, and IS_IOS combined with TOOLKIT_VIEWS."""
    L=s.split('\n');i=0
    while i<len(L):
        if L[i].lstrip().startswith(('#if','#elif')):
            j=i;c=L[i]
            while c.endswith('\\') and j+1<len(L): j+=1;c=c[:-1]+L[j]
            body=c.split(None,1)[1] if len(c.split(None,1))>1 else ''
            pos=('||' in c and 'IS_MAC' in c and '&&' not in c and '!' not in body)
            views='IOS_MOBILE_UI) && defined(TOOLKIT_VIEWS)' in c
            if pos or views:
                for k in range(i,j+1):
                    L[k]=L[k].replace('BUILDFLAG(IOS_MOBILE_UI)','BUILDFLAG(IS_IOS)')
            i=j
        i+=1
    return '\n'.join(L)
def fix_cpp(p):
    s=open(p).read()
    if 'BUILDFLAG(IS_IOS)' not in s: return False
    s=s.replace('BUILDFLAG(IS_IOS)','BUILDFLAG(IOS_MOBILE_UI)')
    s=restore_positive_lists(s)
    if INC not in s:
        if '#include "build/build_config.h"\n' in s:
            s=s.replace('#include "build/build_config.h"\n','#include "build/build_config.h"\n'+INC+'\n',1)
        else:
            m=list(re.finditer(r'^#include .*\n',s,re.M))
            assert m, p
            # put before first #if that uses the flag, after the includes block start
            first=m[0]
            s=s[:first.end()]+INC+'\n'+s[first.end():]
    if not dry: open(p,'w').write(s)
    return True
def fix_gn(p):
    s=open(p).read()
    out=[];changed=False
    for line in s.split('\n'):
        code=line.split('#',1)[0]
        if re.search(r'\bis_ios\b',code) and '"' not in code and 'enable_ios_desktop_views' not in code:
            line=re.sub(r'\bis_ios\b',lambda m:'(is_ios && !enable_ios_desktop_views)',line); changed=True
        out.append(line)
    if not changed: return False
    s='\n'.join(out)
    if 'import("//build/config/ui.gni")' not in s:
        m=re.search(r'^import\(.*\)\n',s,re.M)
        if m: s=s[:m.start()]+'import("//build/config/ui.gni")\n'+s[m.start():]
        else:
            m=re.search(r'\n\n',s); s=s[:m.end()]+'import("//build/config/ui.gni")\n\n'+s[m.end():]
    if not dry: open(p,'w').write(s)
    return True
for a in [x for x in sys.argv[1:] if x!='--dry']:
    paths=[a] if os.path.isfile(a) else [os.path.join(r,f) for r,d,fs in os.walk(a) for f in fs]
    for p in paths:
        if '/ios/' in p.replace(a,'',1) or p.endswith('_ios.mm') or p.endswith('_ios.h') or p.endswith('_ios.cc'): continue
        if p.endswith(('.cc','.h','.mm')) and fix_cpp(p): print('cpp',p)
        elif os.path.basename(p) in ('BUILD.gn',) or p.endswith('.gni'):
            if fix_gn(p): print('gn ',p)
