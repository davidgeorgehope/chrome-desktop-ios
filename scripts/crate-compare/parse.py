import re,sys,glob,os,time
def first(rx,s):
    m=re.search(rx,s); return m
for f in sys.argv[1:]:
    s=open(f,errors='replace').read()
    t=os.path.basename(f)[:-4]
    st=re.search(r'BENCH_LAUNCH (\S+ \S+)',s).group(1)[11:16]
    end=re.search(r'\[\s*([0-9.]+)\] BENCH_END',s); 
    dr=first(r'\[\s*([0-9.]+)\][^\n]*===DESKTOP_READY=== [^\n]*uptime=([0-9.]+)',s)
    bs=first(r'===(?:FIREFOX|CHROMIUM)_START===[^\n]*uptime=([0-9.]+)',s)
    la=re.findall(r'===INTERACTIVE_LAUNCH===[^\n]*up=([0-9.]+)',s)
    sc=re.findall(r'===INTERACTIVE_SCROLL=== fps=([0-9.]+) frames=(\d+)[^\n]*p95_frame_ms=([0-9.]+)',s)
    wn=first(r'===INTERACTIVE_WARM_NAV===[^\n]*up=([0-9.]+)',s); wl=first(r'===INTERACTIVE_WARM_LAUNCH===[^\n]*up=([0-9.]+)',s)
    inp=first(r'===INTERACTIVE_INPUT=== why=(\S+) key_raf_ms=(\S+) click_raf_ms=(\S+)',s)
    cold=float(la[0])-float(bs.group(1)); warm=float(wl.group(1))-float(wn.group(1))
    ws=sc[1][0] if len(sc)>1 else '-'
    print(f"{t:10s} start={st} desk_host={float(dr.group(1)):.2f} desk_up={float(dr.group(2)):.2f} cold={cold:.2f} scroll={sc[0][0]} ({sc[0][1]}f,p95 {sc[0][2]}) warm={warm:.2f} key/click={inp.group(2)}/{inp.group(3)} warmscroll={ws}")
