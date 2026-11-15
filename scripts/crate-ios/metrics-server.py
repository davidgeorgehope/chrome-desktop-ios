#!/usr/bin/env python3
import os, sys, time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = sys.argv[1] if len(sys.argv) > 1 else "/usr/local/share/interactive-metrics"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
LOG = "/var/log/crate-bench.log"
SERIALS = [p for p in ("/dev/ttyAMA0", "/dev/console") if os.path.exists(p)]

def up():
    try:
        return open("/proc/uptime").read().split()[0]
    except Exception:
        return "na"

def stamp(line: str) -> str:
    line = line.rstrip("\n")
    if " up=" not in line and line.startswith("==="):
        line = f"{line} up={up()}"
    return line

def emit(line: str) -> None:
    line = stamp(line)
    msg = line + "\n"
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a") as f:
        f.write(msg)
        f.flush()
    for s in SERIALS:
        try:
            with open(s, "w") as f:
                f.write(msg)
                f.flush()
        except Exception:
            pass

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace")
        for line in body.splitlines():
            if line.strip():
                emit(line)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, fmt, *args):
        return

if __name__ == "__main__":
    os.chdir(ROOT)
    emit(f"===INTERACTIVE_HTTPD=== port={PORT} root={ROOT} pid={os.getpid()}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
