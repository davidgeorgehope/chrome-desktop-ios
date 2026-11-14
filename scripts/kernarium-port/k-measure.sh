#!/bin/bash
# k-measure.sh TAG BROWSER JIT_BUDGET [EXEC_BUDGET] : official uml-darwin 0022 through measure-interactive (4 CPUs, 4G guest), host-stamped.
D=/Users/davidhope/linux-ios-bakeoff/scratch/jitprof
: "${KBIN:?KBIN}"; export KBIN; mkdir -p $D/logs
export NCPUS=4 GUEST_MEM=4G UML_JIT_CACHE_BUDGET=$3
[ -n "$4" ] && export UML_JIT_EXECUTOR_CACHE_BUDGET=$4
if pgrep -f '[c]rate-run --' >/dev/null; then echo "refuse: crate running"; exit 2; fi
python3 $D/bench-run.py $D/logs/$1.log 400 "^STOPPED " -- /Users/davidhope/linux-ios-bakeoff/notes/interactive-pack/scripts/macos-metal/measure-interactive-crate-cmp.sh "$1" - "$2"
grep -aE "===(DESKTOP_READY|FIREFOX_START|CHROMIUM_START|INTERACTIVE_LAUNCH|INTERACTIVE_SCROLL|INTERACTIVE_INPUT|INTERACTIVE_WARM_LAUNCH)===|SWAP_ABORT|LAUNCH .*tag=" $D/logs/$1.log | awk '!seen[substr($0,13)]++' | cut -c1-200
