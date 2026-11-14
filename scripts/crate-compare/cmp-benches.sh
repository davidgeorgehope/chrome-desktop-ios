#!/bin/sh
# Same CPU-bound workloads in any arm64 Linux guest (crate Debian or Kernarium Alpine).
# Times from /proc/uptime (10 ms). Prints ===CMPB=== name secs [hash].
export LC_ALL=C
OUT=${1:-/dev/console}
up() { cut -d' ' -f1 /proc/uptime; }
t() { n=$1; shift; s=$(up); h=$("$@" 2>&1 | md5sum | cut -c1-8); e=$(up)
      echo "===CMPB=== $n $(awk -v a=$s -v b=$e 'BEGIN{printf "%.2f", b-a}') $h" | tee -a $OUT; }
W=/tmp/cmpb; rm -rf $W; mkdir -p $W; cd $W
# A large generated C file: 600 functions with loops, switches and arithmetic.
awk 'BEGIN{print "#include <stdint.h>";
 for(i=0;i<600;i++){printf "uint64_t f%d(uint64_t x,uint64_t y){uint64_t a=x*%d+y;for(int k=0;k<(int)(x&15);k++){switch((a>>k)&7){case 0:a^=a<<13;break;case 1:a+=y*%d;break;case 2:a=(a>>7)|(a<<57);break;case 3:a*=0x9E3779B97F4A7C15ull;break;case 4:a-=x;break;default:a^=%d;}}return a+(y%%%d);}\n",i,i+3,i*7+1,i+11,i+5}
 printf "uint64_t all(uint64_t x){uint64_t s=0;"; for(i=0;i<600;i++)printf "s+=f%d(x,s);",i; print "return s;}"}' > big.c
echo "===CMPB_INFO=== $(uname -m) cpus=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo) gcc=$(gcc -dumpversion 2>/dev/null) node=$(node --version 2>/dev/null) python=$(python3 --version 2>&1 | cut -d' ' -f2) big_c_lines=$(wc -l < big.c)" | tee -a $OUT
t gcc_O2 gcc -O2 -c big.c -o big.o
t gcc_O2_again gcc -O2 -c big.c -o big.o
t node_e0 node -e 0
t node_int_loop node -e 'let s=0;for(let i=0;i<1e8;i++)s=(s+i)|0;console.log(s)'
t node_fp_loop node -e 'let s=0;for(let i=0;i<3e7;i++)s+=Math.sqrt(i);console.log(s.toFixed(0))'
t python_loop python3 -c 's=0
for i in range(3000000): s+=i*i%7
print(s)'
t awk_sqrt_loop awk 'BEGIN{for(i=0;i<3000000;i++)s+=sqrt(i);printf "%.0f\n",s}'
t sha256_50MB sh -c 'head -c 52428800 /dev/zero | sha256sum'
t spawn_1000 sh -c 'i=0; while [ $i -lt 1000 ]; do /bin/true; i=$((i+1)); done'
echo "===CMPB_DONE===" | tee -a $OUT
