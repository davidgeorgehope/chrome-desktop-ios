#!/bin/bash
# cpu-ab.sh TAGPREFIX BIN_A BIN_B : one at a time, A then B, cmp-benches x2 each.
cd $HOME/linux-ios-bakeoff/scratch/jitprof
KBIN=$2 ./k-cpu.sh $1-a > logs/$1-a.out 2>&1
KBIN=$3 ./k-cpu.sh $1-b > logs/$1-b.out 2>&1
echo DONE $(date)
