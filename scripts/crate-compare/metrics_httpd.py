#!/usr/bin/python3
# Python port of Kernarium's metrics-httpd.go: serves the interactive-metrics
# page on 127.0.0.1:8765 and writes POSTed markers (with guest uptime) to the
# serial console and /tmp/interactive-metrics.log.
import http.server, os, sys, time
ROOT = '/usr/local/share/interactive-metrics'
def write(s):
    up = open('/proc/uptime').read().split()[0]
    line = '%s %s up=%s\n' % (time.strftime('%H:%M:%S', time.gmtime()), s.rstrip('\n'), up)
    for p in ('/tmp/interactive-metrics.log', '/dev/ttyAMA0'):
        try:
            with open(p, 'a') as f: f.write(line)
        except Exception: pass
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _txt(self, body):
        b = body.encode(); self.send_response(200)
        self.send_header('Content-Type', 'text/plain'); self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split('?')[0]
        if p in ('/cgi-bin/report', '/report'): return self._txt('ready\n')
        name = {'/': 'index.html', '/index.html': 'index.html', '/warm.html': 'warm.html'}.get(p)
        if not name: self.send_response(404); self.end_headers(); return
        b = open(os.path.join(ROOT, name), 'rb').read(); self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8'); self.send_header('Content-Length', str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0)
        write(self.rfile.read(min(n, 4096)).decode('utf-8', 'replace')); self._txt('ok\n')
http.server.ThreadingHTTPServer(('127.0.0.1', 8765), H).serve_forever()
