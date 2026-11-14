#!/bin/sh
# Step-0 profile guest: phases separated by ===PHASE=== markers; the host
# watcher dumps UML_JIT_PROFILE counters at each marker.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root TERM=linux LC_ALL=C
P=/usr/local/share/cpu-benches; O=/dev/ttyS0
up() { cut -d' ' -f1 /proc/uptime; }
mark() { echo "===PHASE=== $1 $(up)" > $O; sleep 2.5; }
mkdir -p /tmp/apks && tar -C /tmp/apks -xf $P/apks.tar
apk add --allow-untrusted --force-non-repository --no-network /tmp/apks/*.apk >/dev/null 2>&1
W=/tmp/w; mkdir -p $W; cd $W
cp $P/cmp-benches.sh . ; sed -n '/^awk/,/> big.c$/p' cmp-benches.sh > gen.sh; sh gen.sh
printf '.globl _start\n_start: mov x0, #0\n mov x8, #93\n svc #0\n' > tiny.S
gcc -nostdlib -static -o tiny tiny.S
cat > spawner.c <<'C'
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
int main(int c, char **v) { int n = atoi(v[1]); int mode = atoi(v[2]);
  for (int i = 0; i < n; i++) { pid_t p = fork();
    if (p == 0) { if (mode == 0) _exit(0); execl(v[3], v[3], (char *)0); _exit(127); }
    waitpid(p, 0, 0); } return 0; }
C
gcc -O2 -static -o spawner spawner.c
echo "===INFO=== aslr=$(cat /proc/sys/kernel/randomize_va_space) gcc=$(gcc -dumpversion) cpus=$(nproc)" > $O
t() { n=$1; shift; mark "$n"; s=$(up); "$@" >/dev/null 2>&1; e=$(up)
  echo "===T=== $n $(awk -v a=$s -v b=$e 'BEGIN{printf "%.2f", b-a}')" > $O; }
run_set() { sfx=$1
  t fork_exec_true_1000$sfx ./spawner 1000 1 /bin/true
  t sh_true_1000$sfx sh -c 'i=0; while [ $i -lt 1000 ]; do /bin/true; i=$((i+1)); done'
  t sh_true_1000_b$sfx sh -c 'i=0; while [ $i -lt 1000 ]; do /bin/true; i=$((i+1)); done'
  t sh_spawner_1000$sfx sh -c 'i=0; while [ $i -lt 1000 ]; do ./spawner 0 0; i=$((i+1)); done'
  t sh_subshell_1000$sfx sh -c 'i=0; while [ $i -lt 1000 ]; do (:); i=$((i+1)); done'
  t spawner_sh_c_true_300$sfx ./spawner 300 1 /tmp/w/shtrue
}
printf '#!/bin/sh\n/bin/true\n' > /tmp/w/shtrue; chmod 755 /tmp/w/shtrue
run_set _aslr2
echo 0 > /proc/sys/kernel/randomize_va_space
echo "===INFO=== aslr=$(cat /proc/sys/kernel/randomize_va_space)" > $O
run_set _aslr0
mark END
echo "===PROF_DONE===" > $O
sync; poweroff -f
