#!/usr/bin/env python3
"""Report/fix deps the GN walker hoisted out of their original if() chain.
usage: gnchain.py [--fix] BUILD.gn...  (run in chromium src; compares to git HEAD)"""
import re, subprocess, sys
def parse(lines):
    """Return list of chains (tuple of conditions) per line, conditions within target only."""
    chains=[]; stack=[]  # entries: ('if',cond) | ('blk',None)
    i=0; n=len(lines)
    pending=None
    for idx,l in enumerate(lines):
        s=l.split('#',1)[0].strip() if not l.strip().startswith('"') else l.strip()
        chains.append(tuple(c for k,c in stack if k=='if'))
        if pending is not None:
            pending+=' '+s
            if s.endswith('{'):
                stack.append(('if',re.sub(r'^if \((.*)\) \{$',r'\1',pending).strip())); pending=None
            continue
        m=re.match(r'^\} else if \((.*)\) \{$',s)
        if m and stack:
            k,c=stack.pop(); stack.append(('if','!(%s) && (%s)'%(c,m.group(1)))); continue
        if s=='} else {' and stack:
            k,c=stack.pop(); stack.append(('if','!(%s)'%c)); continue
        if s.startswith('if (') :
            if s.endswith('{'): stack.append(('if',re.sub(r'^if \((.*)\) \{$',r'\1',s)))
            else: pending=s
            continue
        opens=s.count('{'); closes=s.count('}')
        for _ in range(closes):
            if stack: stack.pop()
        for _ in range(opens): stack.append(('blk',None))
    return chains
def target_of(lines, idx):
    for j in range(idx,-1,-1):
        m=re.match(r'^\s*(\w+)\("([^"]+)"\)',lines[j])
        if m and m.group(1) not in ('import','assert','if'): return m.group(2)
    return None
fix='--fix' in sys.argv
todo={}
FALSE={'is_chromeos','is_android','is_win','is_linux','is_mac','is_fuchsia','is_castos','is_desktop_android','is_chromeos_device','is_cronet_build','is_ozone','use_ozone','use_aura'}
TRUE={'is_ios','is_apple','is_posix','toolkit_views','use_blink','enable_ios_desktop_views'}
def should_restore(conds):
    for c in conds:
        e=c
        # desktop platform groups count as true for desktop Views on iOS
        if re.search(r'is_mac\b',e) and re.search(r'is_(win|linux)\b',e) and '&&' not in e: continue
        e=e.replace('&&',' and ').replace('||',' or ').replace('!',' not ')
        names=set(re.findall(r'[A-Za-z_]\w*',e))-{'and','or','not'}
        if not names <= (FALSE|TRUE): continue
        env={n:(n in TRUE) for n in names}
        try:
            env2=dict(env); env2['is_ios']=False
            if not eval(e,{},env) and not eval(e,{},env2): return True
        except Exception: pass
    return False
for p in [a for a in sys.argv[1:] if a!='--fix']:
    orig=subprocess.run(['git','show','HEAD:'+p],capture_output=True,text=True).stdout.splitlines()
    new=open(p).read().splitlines()
    oc=parse(orig); nc=parse(new)
    origpos={}
    for i,l in enumerate(orig):
        m=re.match(r'^\s*"(//[^"]+|:[^"]+)",?\s*$',l)
        if m: origpos.setdefault((target_of(orig,i),m.group(1)),[]).append(i)
    for i,l in enumerate(new):
        m=re.match(r'^\s*"(//[^"]+|:[^"]+)",?\s*$',l)
        if not m: continue
        key=(target_of(new,i),m.group(1))
        if key not in origpos: continue
        cands=[[c for c in oc[o] if c not in nc[i]] for o in origpos[key]]
        if any(not c for c in cands): continue
        missing=min(cands,key=len)
        if missing and should_restore(missing):
            todo.setdefault(p,[]).append((i," && ".join("(%s)"%c for c in missing)))
            print(f'{p}:{i+1}: {m.group(1)} [{key[0]}] missing: {" && ".join(missing)}')

# ---- fix mode (appended) ----

def apply(p, items):
    lines=open(p).read().splitlines()
    groups={}
    for i,cond in items:
        # find list start
        d=0; st=None
        for j in range(i-1,-1,-1):
            d+=lines[j].count(']')-lines[j].count('[')
            m=re.match(r'^(\s*)(\w+) \+?= \[',lines[j])
            if d<0 and m: st=j; break
            if d<0: break
        if st is None: print('skip',p,i+1); continue
        if m.group(2) not in ('deps','public_deps','data_deps'): continue
        d=0; en=None
        for j in range(st,len(lines)):
            d+=lines[j].count('[')-lines[j].count(']')
            if d==0: en=j; break
        if en is None or en==st: print('skip1',p,i+1); continue
        m=re.match(r'^(\s*)(\w+) \+?= \[',lines[st])
        groups.setdefault((en,m.group(1),m.group(2),cond),[]).append(i)
    ins={}; rm=set()
    for (en,ind,var,cond),idxs in groups.items():
        deps=[lines[i].strip().rstrip(',') for i in idxs]
        rm|=set(idxs)
        blk=[f'{ind}if ({cond}) {{', f'{ind}  {var} += ['] + [f'{ind}    {d},' for d in deps] + [f'{ind}  ]', f'{ind}}}']
        ins.setdefault(en,[]).extend(blk)
    out=[]
    for j,l in enumerate(lines):
        if j not in rm: out.append(l)
        if j in ins: out.extend(ins[j])
    open(p,'w').write('\n'.join(out)+'\n')
if fix:
    for p,items in todo.items(): apply(p,items)
