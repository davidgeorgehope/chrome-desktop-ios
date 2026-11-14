#!/bin/bash
# crate-launch.sh TAG TIMEOUT_S STOP_REGEX : one crate-run (jit, 4 CPUs, 4 GiB, 2D 1920x1080) under bench-run.py
D=/Users/davidhope/linux-ios-bakeoff/scratch/crate-bench; I=$D/img
if pgrep -f '[u]ml-darwin|[c]rate-run --' >/dev/null; then echo "refuse: another VM running"; exit 2; fi
free=$(memory_pressure | awk '/free percentage/ {print $5+0}'); [ "${free:-0}" -ge 40 ] || { echo "refuse: memory free ${free}%"; exit 3; }
rm -f $D/vnc.sock
exec python3 $D/bench-run.py $D/logs/$1.log "$2" "$3" -- caffeinate -dims $D/crate/target/release/crate-run \
  --backend jit --cpus 4 --memory 4096 \
  --kernel $I/debian-xfce-vmlinuz --initrd $I/debian-xfce-initrd.img \
  --cmdline "console=ttyAMA0 root=/dev/vda rw" \
  --disk $I/disk.img --disk $I/seed.iso,ro \
  --display 2d --modes 1920x1080 --vnc $D/vnc.sock --forward 2230:22
