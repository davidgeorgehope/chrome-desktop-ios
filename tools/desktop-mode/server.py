import http.server, json, time, sys
LOG='/tmp/uaecho/log.jsonl'
HINTS='Sec-CH-UA, Sec-CH-UA-Mobile, Sec-CH-UA-Platform, Sec-CH-UA-Platform-Version, Sec-CH-UA-Full-Version-List, Sec-CH-UA-Model, Sec-CH-UA-Arch, Sec-CH-UA-Form-Factors'
PAGE='''<!doctype html><html><head><meta charset=utf-8>%s<title>UA echo</title>
<style>body{font:18px -apple-system,sans-serif;margin:16px}td{padding:2px 10px;border-bottom:1px solid #ddd;vertical-align:top}td:first-child{font-weight:600;white-space:nowrap}.p{color:#080}.f{color:#c00}</style></head>
<body><h2>UA echo %s</h2><table id=t></table><pre id=h></pre><script>
(async()=>{const v={};const d=navigator.userAgentData;
v.userAgent=navigator.userAgent;v.platform=navigator.platform;v.vendor=navigator.vendor;
v.uaData_mobile=d?d.mobile:'n/a';v.uaData_platform=d?d.platform:'n/a';v.uaData_brands=d?d.brands.map(b=>b.brand+' '+b.version).join(', '):'n/a';
if(d){try{const h=await d.getHighEntropyValues(['platformVersion','model','architecture','formFactors','fullVersionList']);v.he_platformVersion=h.platformVersion;v.he_model=JSON.stringify(h.model);v.he_arch=h.architecture;v.he_formFactors=JSON.stringify(h.formFactors);}catch(e){v.he_error=String(e)}}
v.maxTouchPoints=navigator.maxTouchPoints;v.ontouchstart=('ontouchstart' in window);
v.pointer_fine=matchMedia('(pointer: fine)').matches;v.pointer_coarse=matchMedia('(pointer: coarse)').matches;v.any_pointer_coarse=matchMedia('(any-pointer: coarse)').matches;v.hover=matchMedia('(hover: hover)').matches;
v.innerWidth=innerWidth;v.innerHeight=innerHeight;v.clientWidth=document.documentElement.clientWidth;v.screen=screen.width+'x'+screen.height;v.dpr=devicePixelRatio;v.vv_scale=visualViewport?visualViewport.scale:'n/a';v.location=location.href;
const t=document.getElementById('t');for(const k in v){const r=t.insertRow();r.insertCell().textContent=k;r.insertCell().textContent=String(v[k]);}
document.getElementById('h').textContent=%s;
fetch('/log',{method:'POST',body:JSON.stringify({page:location.href,js:v})});})();
</script></body></html>'''
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        hdr={k:v for k,v in self.headers.items() if k.lower().startswith('sec-ch') or k.lower() in ('user-agent','accept-language')}
        open(LOG,'a').write(json.dumps({'t':time.strftime('%H:%M:%S'),'path':self.path,'headers':hdr})+'\n')
        vp='<meta name=viewport content="width=400">' if 'vp=400' in self.path else ''
        body=(PAGE%(vp,'(meta viewport width=400)' if vp else '',json.dumps('Request headers:\n'+'\n'.join(f'{k}: {v}' for k,v in hdr.items())))).encode()
        self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Accept-CH',HINTS);self.send_header('Critical-CH',HINTS);self.send_header('Cache-Control','no-store')
        self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def do_POST(self):
        n=int(self.headers.get('Content-Length',0));data=self.rfile.read(n).decode()
        open(LOG,'a').write(json.dumps({'t':time.strftime('%H:%M:%S'),'path':'POST '+self.path,'js':json.loads(data)})+'\n')
        self.send_response(204);self.end_headers()
http.server.ThreadingHTTPServer(('127.0.0.1',8765),H).serve_forever()
