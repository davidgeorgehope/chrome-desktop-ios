# Minimal stdlib CDP client for the sim Views build ONLY ([::1]:9333).
import json, socket, base64, os, struct, sys, urllib.request
PORT=9333; HOST='127.0.0.1'
import subprocess
_own=subprocess.run(['lsof','-nP',f'-iTCP:{PORT}','-sTCP:LISTEN'],capture_output=True,text=True).stdout
if 'chrome_vi' not in _own or 'Google' in _own:
    raise SystemExit('refusing: port %d is not owned by chrome_views_ios' % PORT)
PROBE = r"""(async()=>{const v={};const d=navigator.userAgentData;
v.location=location.href;v.title=document.title;v.userAgent=navigator.userAgent;v.platform=navigator.platform;
v.uaData_mobile=d?d.mobile:'n/a';v.uaData_platform=d?d.platform:'n/a';
v.maxTouchPoints=navigator.maxTouchPoints;v.ontouchstart=('ontouchstart' in window);
v.pointer_fine=matchMedia('(pointer: fine)').matches;v.hover=matchMedia('(hover: hover)').matches;
v.innerWidth=innerWidth;v.clientWidth=document.documentElement.clientWidth;v.dpr=devicePixelRatio;
v.vv_scale=visualViewport?visualViewport.scale:'n/a';
const m=document.querySelector('meta[name=viewport]');v.meta_viewport=m?m.content:null;
return JSON.stringify(v);})()"""
def targets():
    return json.load(urllib.request.urlopen(f'http://{HOST}:{PORT}/json',timeout=5))
def ws(url):
    path=url.split(f':{PORT}',1)[1]
    s=socket.create_connection((HOST,PORT),timeout=30)
    key=base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET {path} HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    buf=b''
    while b'\r\n\r\n' not in buf: buf+=s.recv(4096)
    if b' 101 ' not in buf.split(b'\r\n')[0]: raise SystemExit('ws handshake failed')
    return s
def send(s,obj):
    data=json.dumps(obj).encode(); mask=os.urandom(4); n=len(data)
    hdr=bytes([0x81]) + (bytes([0x80|n]) if n<126 else bytes([0x80|126])+struct.pack('>H',n) if n<65536 else bytes([0x80|127])+struct.pack('>Q',n))
    s.sendall(hdr+mask+bytes(b^mask[i%4] for i,b in enumerate(data)))
def recvn(s,n):
    b=b''
    while len(b)<n:
        c=s.recv(n-len(b))
        if not c: raise EOFError
        b+=c
    return b
def recv(s):
    h=recvn(s,2); n=h[1]&0x7f
    if n==126: n=struct.unpack('>H',recvn(s,2))[0]
    elif n==127: n=struct.unpack('>Q',recvn(s,8))[0]
    return json.loads(recvn(s,n))
def call(s,i,method,params=None):
    send(s,{'id':i,'method':method,'params':params or {}})
    while True:
        m=recv(s)
        if m.get('id')==i: return m
if __name__=='__main__':
    page=[t for t in targets() if t.get('type')=='page']
    if not page: raise SystemExit('no page target')
    s=ws(page[0]['webSocketDebuggerUrl'])
    r=call(s,1,'Runtime.evaluate',{'expression':PROBE,'awaitPromise':True,'returnByValue':True})
    print(r['result']['result'].get('value') or json.dumps(r)[:400])
