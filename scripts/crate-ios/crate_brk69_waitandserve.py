"""Import this in lldb -b: wait for Crate, attach, bless brk #0x69 requests."""
from __future__ import annotations

import os
import sys

# Reuse the serve implementation from the sibling module.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crate_brk69_serve as core  # noqa: E402


def __lldb_init_module(debugger, _internal) -> None:  # noqa: ANN001
    log = os.environ.get("CRATE_BRK69_LOG", "/tmp/k-harness/logs/crate-ios-d4-brk69.log")
    timeout = os.environ.get("CRATE_BRK69_TIMEOUT", "240")
    debugger.HandleCommand("settings set auto-confirm true")
    debugger.HandleCommand("process attach --name Crate --waitfor")
    debugger.HandleCommand(
        f"command script add -f crate_brk69_serve.serve crate_brk69_serve"
    )
    # Call serve in-process so a batch-mode abort cannot skip it after attach.
    core.serve(debugger, f"--log {log} --timeout {timeout}", None, None, None)
