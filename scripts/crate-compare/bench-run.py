#!/usr/bin/env python3
"""bench-run.py LOG TIMEOUT_S STOP_REGEX -- CMD...
Runs CMD with a pipe for stdin, writes every output line to LOG prefixed with
host seconds since launch ("[  12.345] ..."), stops CMD when STOP_REGEX has
matched (plus 3 s) or after TIMEOUT_S. Swap guard: kills CMD if swap used
grows more than 2048 MiB over the start. Sends Ctrl-A x first (crate-run's
quit), then TERM, then KILL. Prints first-seen times of the main markers."""
import os, re, signal, subprocess, sys, threading, time
log, timeout, stop = sys.argv[1], float(sys.argv[2]), sys.argv[3]
cmd = sys.argv[sys.argv.index('--') + 1:]
def swap():
    out = subprocess.run(['sysctl', 'vm.swapusage'], capture_output=True, text=True).stdout
    m = re.search(r'used = ([0-9.]+)M', out); return float(m.group(1)) if m else 0.0
s0 = swap(); t0 = time.time()
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
f = open(log, 'a', buffering=1)
f.write('[%9.3f] BENCH_LAUNCH %s epoch=%.3f swap_start=%.0fM cmd=%s\n' % (0, time.strftime('%Y-%m-%d %H:%M:%S %Z'), t0, s0, ' '.join(cmd)))
seen = {}; stop_at = [None]; why = ['exit']
keys = ['DESKTOP_READY', 'FIREFOX_START', 'CHROMIUM_START', 'INTERACTIVE_LAUNCH', 'INTERACTIVE_SCROLL=', 'INTERACTIVE_READY_FOR_INPUT', 'INTERACTIVE_INPUT=', 'INTERACTIVE_WARM_LAUNCH', 'login:']
def guard():
    while p.poll() is None:
        u = swap()
        if u > s0 + 2048:
            f.write('[%9.3f] SWAP_ABORT used=%.0fM start=%.0fM\n' % (time.time() - t0, u, s0)); why[0] = 'swap'; stop_at[0] = time.time(); return
        if time.time() - t0 > timeout and stop_at[0] is None:
            why[0] = 'timeout'; stop_at[0] = time.time()
        time.sleep(2)
threading.Thread(target=guard, daemon=True).start()
def killer():
    while p.poll() is None:
        if stop_at[0] and time.time() >= stop_at[0]:
            try: p.stdin.write(b'\x01x'); p.stdin.flush()
            except Exception: pass
            for sig, wait in ((signal.SIGTERM, 8), (signal.SIGKILL, 3)):
                for _ in range(int(wait * 10)):
                    if p.poll() is not None: return
                    time.sleep(0.1)
                try: os.killpg(p.pid, sig)
                except Exception: pass
            return
        time.sleep(0.2)
threading.Thread(target=killer, daemon=True).start()
rx = re.compile(stop)
buf = b''
while True:
    chunk = p.stdout.read1(65536) if hasattr(p.stdout, 'read1') else os.read(p.stdout.fileno(), 65536)
    if not chunk: break
    buf += chunk
    while b'\n' in buf:
        line, buf = buf.split(b'\n', 1)
        t = time.time() - t0
        s = line.decode('utf-8', 'replace').rstrip('\r')
        f.write('[%9.3f] %s\n' % (t, s))
        for k in keys:
            if k in s and k not in seen: seen[k] = t
        if stop_at[0] is None and rx.search(s): why[0] = 'stop'; stop_at[0] = time.time() + 3
p.wait()
f.write('[%9.3f] BENCH_END why=%s rc=%s\n' % (time.time() - t0, why[0], p.returncode))
print('why=%s rc=%s ' % (why[0], p.returncode) + ' '.join('%s=%.2f' % (k.rstrip('=:'), v) for k, v in seen.items()))
