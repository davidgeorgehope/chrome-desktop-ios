#!/usr/bin/env python3
# Closed-loop cursor move on the phone trackpad (simulator only): tp-goto.py X Y
import sys, subprocess, re, glob, os, time
U=os.environ.get('SIM_UDID', 'booted')
R=sorted(glob.glob(os.path.expanduser('~/chromium-build/logs/views-m2/run/*')), key=os.path.getmtime)[-1]
tx,ty=float(sys.argv[1]),float(sys.argv[2])
def cur():
    t=open(R+'/stderr.txt',errors='ignore').read()
    m=re.findall(r'trackpad cursor=\{([-\d.]+), ([-\d.]+)\}',t)
    return (float(m[-1][0]),float(m[-1][1])) if m else None
def sw(dx,dy):
    cx,cy=233,330
    sx,sy=cx-dx/2,cy-dy/2
    subprocess.run(['axe','swipe','--start-x',str(int(sx)),'--start-y',str(int(sy)),'--end-x',str(int(sx+dx)),'--end-y',str(int(sy+dy)),'--duration','0.5','--udid',U],capture_output=True)
    time.sleep(1.6)
gx=gy=2.4
last=None
for i in range(10):
    c=cur()
    if c is None: sw(-180,-150); continue
    if last:
        (lc,ldx,ldy)=last
        if abs(ldx)>20 and lc[0]+0<c[0]<1919 and 0<lc[0]<1919: gx=max(1.0,min(5.0,(c[0]-lc[0])/ldx))
        if abs(ldy)>20 and 0<c[1]<1079 and 0<lc[1]<1079: gy=max(1.0,min(5.0,(c[1]-lc[1])/ldy))
    ex,ey=tx-c[0],ty-c[1]; print(i,c,round(gx,2),round(gy,2),file=sys.stderr)
    if abs(ex)<6 and abs(ey)<6: break
    dx,dy=ex/gx,ey/gy
    if (dx*dx+dy*dy)**0.5<14:   # too short: would register as a tap; detour
        sw(-25 if ex>=0 else 25, -25 if ey>=0 else 25); last=None; continue
    dx=max(-380,min(380,dx)); dy=max(-450,min(450,dy))
    sw(dx,dy); last=(c,dx,dy)
print('cursor', cur())
