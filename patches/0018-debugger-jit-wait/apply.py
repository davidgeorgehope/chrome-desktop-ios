#!/usr/bin/env python3
"""Insert the wait-for-debugger and bench-delay hooks. Run from the Kernarium
tree after patches/0017-kernarium-serial-log. Idempotent."""
from pathlib import Path
import sys

cv = Path("Kernarium/Kernarium/ContentView.swift")
gs = Path("Kernarium/KernariumTests/GuestSessionTests.swift")
if not cv.is_file() or not gs.is_file():
    sys.exit("run from the Kernarium tree after 0017 (missing ContentView or GuestSessionTests)")

COMMENT = """            // Designed-for-iPad xcodebuild test does not ptrace the host
            // process. A checkout can wait here so an Aqua debugserver/lldb
            // can attach (get-task-allow) before the debugger-prepared JIT
            // region is requested.
"""

WAIT = r"""            let env = ProcessInfo.processInfo.environment
            if env["KERNARIUM_WAIT_FOR_DEBUGGER"] == "1" {
                let seconds = env["KERNARIUM_WAIT_FOR_DEBUGGER_TIMEOUT"].flatMap(Double.init) ?? 30
                let deadline = Date().addingTimeInterval(seconds)
                var attached = kernarium_runtime_loader_debugger_attached() != 0
                print("Kernarium: waiting up to \(Int(seconds))s for a debugger")
                while !attached, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                    attached = kernarium_runtime_loader_debugger_attached() != 0
                }
                print("Kernarium: debugger attached=\(attached)")
            }
"""

text = cv.read_text()
if "KERNARIUM_WAIT_FOR_DEBUGGER" in text:
    print("ContentView.swift already has the wait")
else:
    needle = "        let worker = Thread {\n            let result = runGuest("
    insert = "        let worker = Thread {\n" + COMMENT + WAIT + "            let result = runGuest("
    if needle not in text:
        sys.exit("ContentView.swift: did not find `let worker = Thread {` / runGuest")
    cv.write_text(text.replace(needle, insert, 1))
    print("patched ContentView.swift")

text = gs.read_text()
if "KERNARIUM_GUEST_SESSION_BENCH_DELAY" in text:
    print("GuestSessionTests.swift already has the delay")
else:
    old_begin = '        print("KERNARIUM_SESSION_BEGIN|log=\\(log.lastPathComponent)|serial=\\(serialName)|benches=\\(wantBenches)")\n'
    new_begin = (
        '        let benchDelay = environment["KERNARIUM_GUEST_SESSION_BENCH_DELAY"].flatMap(Double.init) ?? 0\n'
        '        print("KERNARIUM_SESSION_BEGIN|log=\\(log.lastPathComponent)|serial=\\(serialName)|benches=\\(wantBenches)|delay=\\(benchDelay)")\n'
    )
    if old_begin not in text:
        sys.exit("GuestSessionTests.swift: unexpected SESSION_BEGIN (apply 0017 first)")
    text = text.replace(old_begin, new_begin, 1)
    old_ready = """        var readySeen = false
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 2)
            let serial = (try? String(contentsOf: serialURL, encoding: .utf8)) ?? ""
            if !readySeen, serial.contains("===DESKTOP_READY===") {
                readySeen = true
                print("KERNARIUM_SESSION_DESKTOP_READY")
            }
            if wantBenches, readySeen, !benchesSent {
"""
    new_ready = """        var readySeen = false
        var readyAt: Date?
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 2)
            let serial = (try? String(contentsOf: serialURL, encoding: .utf8)) ?? ""
            if !readySeen, serial.contains("===DESKTOP_READY===") {
                readySeen = true
                readyAt = Date()
                print("KERNARIUM_SESSION_DESKTOP_READY")
            }
            let delayElapsed = readyAt.map { Date().timeIntervalSince($0) >= benchDelay } ?? false
            if wantBenches, readySeen, delayElapsed, !benchesSent {
"""
    if old_ready not in text:
        sys.exit("GuestSessionTests.swift: unexpected ready/bench loop (apply 0017 first)")
    gs.write_text(text.replace(old_ready, new_ready, 1))
    print("patched GuestSessionTests.swift")
