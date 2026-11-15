"""lldb helper for crate-ios: bless a code region requested with brk #0x69.

crate maps RX pages, then stops on brk #0x69 with the start in x0 and the
length in x1. A debugger writes one byte into each 16 KiB page through
debugserver (the access that makes the pages runnable on iOS 26+), leaves
the start address in x0, and resumes past the instruction. An error is
signaled by putting a value other than the start address in x0.
"""
from __future__ import annotations

import argparse
import re
import shlex
import sys
import time
from collections.abc import Callable
from pathlib import Path

# brk #0x69
BRK_WORD = 0xD4200D20
PAGE_BYTES = 0x4000
BLESSING_BYTE = 0x69
PACKET_RETRIES = 3


def _packet(interpreter: object, text: str) -> tuple[str, bool]:
    import lldb

    result = lldb.SBCommandReturnObject()
    interpreter.HandleCommand(f'process plugin packet send "{text}" --', result)
    out = (result.GetOutput() or "") + (result.GetError() or "")
    found = re.search(r"response: (.*)", out)
    return (found.group(1).strip() if found else ""), result.Succeeded()


def serve(debugger, command, _context, _result, _internal) -> None:  # noqa: ANN001
    options = argparse.ArgumentParser(prog="crate_brk69_serve")
    options.add_argument("--log", type=Path)
    options.add_argument("--timeout", type=float, default=240)
    parsed = options.parse_args(shlex.split(command))
    log_file = parsed.log.open("a", encoding="utf-8") if parsed.log else None

    def log(message: str) -> None:
        line = time.strftime("%H:%M:%S ") + message
        sys.stderr.write(line + "\n")
        if log_file is not None:
            log_file.write(line + "\n")
            log_file.flush()

    try:
        _serve(debugger, parsed.timeout, log)
    except Exception:
        import traceback

        log("the debugger script failed:\n" + traceback.format_exc())
        raise


def _serve(debugger, timeout: float, log: Callable[[str], None]) -> None:  # noqa: ANN001
    import lldb

    interpreter = debugger.GetCommandInterpreter()
    process = debugger.GetSelectedTarget().GetProcess()
    deadline = time.monotonic() + timeout
    while (
        process.GetState()
        not in (lldb.eStateStopped, lldb.eStateExited, lldb.eStateDetached)
        and time.monotonic() < deadline
    ):
        time.sleep(0.05)
    if process.GetState() != lldb.eStateStopped:
        log(f"the process is not stopped (state {process.GetState()}); nothing to serve")
        return
    log(f"attached to pid {process.GetProcessID()}")
    for name in ("SIGBUS", "SIGSEGV", "SIGILL"):
        interpreter.HandleCommand(
            f"process handle {name} -p true -s false -n false",
            lldb.SBCommandReturnObject(),
        )

    def write_byte(address: int) -> bool:
        for _ in range(PACKET_RETRIES):
            reply, ok = _packet(interpreter, f"M{address:x},1:{BLESSING_BYTE:02x}")
            if ok and reply in ("OK", ""):
                return True
        return False

    def prepare(address: int, length: int) -> int:
        if length == 0:
            return address
        if address == 0 or address % PAGE_BYTES != 0:
            log(f"refused: bad address {address:#x} length {length:#x}")
            return 0
        pages = (length + PAGE_BYTES - 1) // PAGE_BYTES
        started = time.monotonic()
        for page in range(pages):
            if not write_byte(address + page * PAGE_BYTES):
                log(f"the write at page {page} of {pages} failed")
                return 0
        log(
            f"prepared {address:#x}+{length:#x}: {pages} pages in "
            f"{time.monotonic() - started:.1f} s"
        )
        return address

    debugger.SetAsync(False)
    blessed = 0
    repeats = {}
    while time.monotonic() < deadline:
        error = process.Continue()
        if error.Fail():
            log(f"continue failed: {error.GetCString()}")
            return
        state = process.GetState()
        if state in (lldb.eStateExited, lldb.eStateDetached):
            log(f"the process ended (state {state})")
            return
        handled = False
        for thread in process:
            frame = thread.GetFrameAtIndex(0)
            pc = frame.GetPC()
            failure = lldb.SBError()
            word = process.ReadUnsignedFromMemory(pc, 4, failure)
            if failure.Fail() or word != BRK_WORD:
                continue
            address = frame.FindRegister("x0").GetValueAsUnsigned()
            length = frame.FindRegister("x1").GetValueAsUnsigned()
            log(f"brk #0x69 request address={address:#x} length={length:#x}")
            result = prepare(address, length)
            frame.FindRegister("x0").SetValueFromCString(f"{result:#x}")
            frame.SetPC(pc + 4)
            blessed += 1
            handled = True
            break
        if not handled:
            thread = process.GetSelectedThread()
            frame = thread.GetFrameAtIndex(0)
            pc = frame.GetPC()
            desc = thread.GetStopDescription(200) or ""
            repeats[pc] = repeats.get(pc, 0) + 1
            if repeats[pc] <= 2:
                log(f"another stop: {desc} pc={pc:#x}")
            if "Fatal error" in desc or repeats[pc] >= 3:
                log(
                    "leaving the process stopped after a non-brk-#0x69 trap "
                    f"(pc={pc:#x}, repeats={repeats[pc]})"
                )
                return
    log(f"the time is up after {blessed} region request(s)")


def __lldb_init_module(debugger, _internal) -> None:  # noqa: ANN001
    debugger.HandleCommand(
        f"command script add -f {Path(__file__).stem}.serve crate_brk69_serve"
    )
