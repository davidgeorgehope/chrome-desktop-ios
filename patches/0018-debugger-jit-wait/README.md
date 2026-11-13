# Designed-for-iPad debugger JIT (wait + serve)

`xcodebuild test` on `platform=macOS,variant=Designed for iPad` does not
ptrace the host process, even with `get-task-allow`. A runtime built with
`UML_IOS_DEBUGGER_JIT=ON` then logs `running on gadgets, not the JIT: no
debugger is attached` unless something else attaches before the guest starts
and actually serves `brk #0xf00d`.

This is the same blessing protocol Henge / StikDebug uses on device
(`brk #0xf00d`, `x16 == 1` to prepare, one `0x69` byte written through the
debugger into each 16 KiB page, then `x16 == 0` to detach). On My Mac, do
not use StikDebug or install anything on a phone: attach host `lldb` and run
Kernarium's own helper, `tests/integration/support/ios_jit_debugger.py`
(`jit_serve`). A bare `lldb -o continue` stops on the trap and never
prepares the region.

Run `python3 patches/0018-debugger-jit-wait/apply.py` from the Kernarium tree after 0017 (idempotent):

- `ContentView.swift`: if `KERNARIUM_WAIT_FOR_DEBUGGER=1`, the worker thread
  waits (default 30 s, override with `KERNARIUM_WAIT_FOR_DEBUGGER_TIMEOUT`)
  until `kernarium_runtime_loader_debugger_attached()` is true, then
  `runGuest`.
- `GuestSessionTests.swift`: `KERNARIUM_GUEST_SESSION_BENCH_DELAY` holds the
  CPU benches that many seconds after `===DESKTOP_READY===` so Firefox
  time-to-first-page can be captured first. Default remains 0.

Rebuild the ios-device runtime with the debugger route, then package it:

```
cmake --preset kernarium-ios-device -DUML_IOS_DEBUGGER_JIT=ON
# then the Linux-only packager, e.g.
~/linux-ios-bakeoff/notes/package-ios-linux-device.sh
```

Confirm the packaged framework has `UML_JIT_MEMORY_REGION_ROUTE`. Launch
`GuestSessionTests` from a one-shot Aqua LaunchAgent in `gui/501` (same
codesign path as 0016) with `TEST_RUNNER_KERNARIUM_WAIT_FOR_DEBUGGER=1` and
a waiter that, as soon as `pgrep -x Kernarium` appears, runs:

```
lldb -b \
  -o "settings set auto-confirm true" \
  -o "process attach --pid $pid" \
  -o "command script import $KERNARIUM/tests/integration/support/ios_jit_debugger.py" \
  -o "jit_serve --log $HOME/Library/Logs/kernarium-ipad-jit-serve.log --timeout 900"
```

Success looks like:

```
Kernarium: debugger attached=true
prepared 0x…+0x…: N pages in … s
detach requested
Kernarium: execution engine jit (cache budget … bytes)
```

and must not say `running on gadgets`. After detach the pages stay
runnable. Do not install this build on a physical iPhone.
