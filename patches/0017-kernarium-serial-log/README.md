# Designed-for-iPad guest serial log and optional CPU benches

Designed-for-iPad has no `simctl console-pty`. `GuestSessionTests` already
tees application stdout into Documents, but guest serial is delivered only to
the in-app console handler.

With `KERNARIUM_SERIAL_LOG=<basename>` set (via `TEST_RUNNER_KERNARIUM_SERIAL_LOG`
under `xcodebuild test`), `SerialConsoleController` also appends raw guest
serial to that file in Documents.

When `KERNARIUM_GUEST_SESSION=1` and `KERNARIUM_GUEST_SESSION_BENCHES=1`, the
guest-session test waits for `===DESKTOP_READY===` in that log, sends the
CPU benches (`sh` loop, 32 MiB `sha256sum`, `openssl speed -evp` after
`apk add openssl` if needed) on the serial console, and `poweroff -f` after
`===BENCH_DONE===`. Default session timeout remains 1800 s unless
`KERNARIUM_GUEST_SESSION_TIMEOUT` is set.

Apply `serial-log.patch` in the Kernarium tree after the bundle-ID change.
