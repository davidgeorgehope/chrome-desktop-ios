# crate-ios bakeoff scripts

Guest image and bench helpers used for the Debian 13 Xfce crate-ios runs
on D4iPad-on-Mac and (the same disk) on Daddy's iPhone 16 Pro.

- `make-seed.py` writes a CIDATA seed. Autologin and the home `chown` live
  in user-data (vendor-data autologin was not enough). The login hash is
  built at bake time from `CRATE_BENCH_PASS`; do not commit that password
  or a seed.img.
- `install-packages.sh` and `crate-bench.sh` install Chromium / Firefox
  (Firefox uses a clean `--no-remote -profile /tmp/crate-ff-profile`) and
  run cold / scroll / warm / gcc_O2 / spawn. The bench script starts the
  metrics httpd itself if port 8765 is down.
- `crate_brk69_serve.py` and `crate_brk69_waitandserve.py` are the D4iPad
  lldb waiter: attach to Crate, bless each 16 KiB page of the `brk #0x69`
  code-region request, then resume. Device JIT uses built-in StikJIT.
- `launch-crate.sh` is the D4 overlap-guard + waiter + open helper.
- `fp-sampler.sh` samples host footprint on macOS; there is no `footprint`
  binary on a physical iPhone.

These scripts are ours. They do not copy crate-ios sources.
