#!/usr/bin/env python3
import os, pty, select, subprocess, sys, time, tty, termios

UDID = "8C95FCCB-F375-4B29-BF3B-1CBEBB6F2EEB"
BUNDLE = "com.imxieyi.Kernarium"
ROOTFS = "alpine-3.24.2-minimal.ext4"
OUT = "/Users/davidhope/linux-ios-bakeoff/notes/kernarium-benches.log"

def main():
    log = open(OUT, "w", buffering=1)
    def logprint(*a):
        s = " ".join(str(x) for x in a)
        print(s, flush=True)
        log.write(s + "\n")

    subprocess.run(["xcrun", "simctl", "terminate", UDID, BUNDLE],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)

    master, slave = pty.openpty()
    env = os.environ.copy()
    env["SIMCTL_CHILD_KERNARIUM_ROOTFS"] = ROOTFS
    proc = subprocess.Popen(
        ["xcrun", "simctl", "launch", "--console-pty", UDID, BUNDLE],
        stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True,
    )
    os.close(slave)
    buf = b""

    def read_more(timeout=1.0):
        nonlocal buf
        end = time.time() + timeout
        got = b""
        while time.time() < end:
            rem = end - time.time()
            r, _, _ = select.select([master], [], [], max(0.05, rem))
            if not r:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            got += chunk
            # keep reading if more is immediately available
            end = min(end, time.time() + 0.15)
        return got

    def wait_for(token, timeout=30):
        deadline = time.time() + timeout
        while time.time() < deadline:
            read_more(min(1.0, deadline - time.time()))
            if token.encode() in buf.replace(b"\r", b""):
                return True
            # ansi-stripped?
            text = buf.decode("utf-8", "replace")
            if token in text:
                return True
        return False

    def send(cmd):
        os.write(master, (cmd + "\n").encode())

    logprint("waiting for shell...")
    if not wait_for("alpine:~#", 40):
        logprint("TIMEOUT waiting for prompt")
        logprint(buf.decode("utf-8", "replace")[-2000:])
        sys.exit(1)
    logprint("SHELL_READY", time.strftime("%Y-%m-%d %H:%M:%S"))

    # Silence local echo so markers only appear when actually printed.
    send("stty -echo")
    time.sleep(0.4)
    read_more(0.5)

    commands = [
        ("uname", "uname -a"),
        ("cat_os_release", "cat /etc/os-release | head -5"),
        ("sh_loop", "TIMEFORMAT='real %R user %U sys %S'; time sh -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'"),
        ("dd_null", "dd if=/dev/zero of=/dev/null bs=1M count=32 2>&1"),
        ("dd_write32", "dd if=/dev/zero of=/tmp/32m bs=1M count=32 2>&1"),
        ("sha256_32m", "TIMEFORMAT='real %R user %U sys %S'; time sha256sum /tmp/32m"),
        ("apk_add_tree", "TIMEFORMAT='real %R user %U sys %S'; time apk add --no-cache tree; echo APK_TREE_EXIT:$?; tree --version | head -1"),
        ("apk_add_openssl", "TIMEFORMAT='real %R user %U sys %S'; time apk add --no-cache openssl; echo APK_OPENSSL_EXIT:$?; openssl version"),
        ("openssl_speed", "openssl speed -seconds 3 -evp sha256 aes-256-cbc"),
        ("done_marker", "echo BENCH_DONE"),
    ]

    for name, cmd in commands:
        begin = f"===BEGIN_{name}==="
        endm = f"===END_{name}==="
        wrapped = "printf '%s\\n' " + begin + "; " + cmd + "; printf '%s\\n' " + endm
        start_len = len(buf)
        send(wrapped)
        timeout = 120 if ("openssl" in name or "apk" in name) else 40
        deadline = time.time() + timeout
        found = False
        while time.time() < deadline:
            read_more(0.4)
            text = buf[start_len:].decode("utf-8", "replace")
            lines = [ln.replace("\r", "").strip() for ln in text.splitlines()]
            if any(ln == endm for ln in lines):
                found = True
                break
        snippet = buf[start_len:].decode("utf-8", "replace")
        logprint(f"\n######## {name} {'OK' if found else 'TIMEOUT'} ########")
        logprint(snippet)
        if not found:
            logprint("WARN missing end marker for", name)

    logprint("\n======== FULL CONSOLE TAIL ========")
    logprint(buf.decode("utf-8", "replace")[-8000:])
    # leave the guest running for screenshots
    os.close(master)
    logprint("BENCH_SCRIPT_OK")

if __name__ == "__main__":
    main()
