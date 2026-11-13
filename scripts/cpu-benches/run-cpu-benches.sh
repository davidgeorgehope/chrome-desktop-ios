#!/bin/sh
# CPU benches for host-native vs UML JIT guest. Safe to run on macOS or Alpine.
# Prints parseable markers. OpenSSL path can be overridden with OPENSSL_BIN.
export PATH="/opt/homebrew/opt/openssl/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:/usr/local/sbin"
export HOME="${HOME:-/root}"
export LANG=C

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TINY="$HERE/tiny-sha"
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
SH_FOR_LOOP="${SH_FOR_LOOP:-/bin/sh}"
CPU_BENCH_ONLY="${CPU_BENCH_ONLY:-}"
# CPU_BENCH_ONLY=sh_loop|compile runs just that bench (compile still installs apk).

run() {
  echo
  echo "======== $1 ========"
  shift
  "$@"
}

# Portable-ish wall/user/sys. Prefer GNU/BSD time -p if the builtin hides it.
time_run() {
  label="$1"
  shift
  echo
  echo "======== $label ========"
  if command -v /usr/bin/time >/dev/null 2>&1; then
    /usr/bin/time -p "$@"
  else
    time "$@"
  fi
}

{
  echo "===BENCH_START==="
  date
  echo "HOST_OR_GUEST: $(uname -s) $(uname -m) $(uname -r)"
  echo "uptime: $(cat /proc/uptime 2>/dev/null || echo host)"
  echo "SHELL_FOR_LOOP: $SH_FOR_LOOP"
  "$SH_FOR_LOOP" -c 'echo SHELL_ID: ${BASH_VERSION:-${ZSH_VERSION:-ash-or-dash-or-other}}'
  echo "OPENSSL_BIN: $OPENSSL_BIN"
  "$OPENSSL_BIN" version 2>/dev/null || echo "openssl missing"
  echo "CC: ${CC:-cc}"
  echo "CPUINFO_FEATURES:"
  if [ -r /proc/cpuinfo ]; then
    grep -E "Features|CPU implementer|CPU part" /proc/cpuinfo | sort -u
  else
    sysctl -a 2>/dev/null | grep -i "hw.optional.arm" | head -40
  fi
  echo "GETAUXVAL_HWCAP:"
  if [ -r /proc/self/auxv ]; then
    # od is portable enough for a hex dump of AT_HWCAP
    od -An -tx8 /proc/self/auxv 2>/dev/null | head -4
  fi
  ${CC:-cc} --version 2>/dev/null | head -1 || true

  run uname uname -a
  # Install dash alone, early, so the 20k loop can be timed with the same
  # shell family as macOS /bin/dash. The full toolchain pack stays in the
  # compile section. Isolated sh_loop profiles skip this so their reset
  # window is still just the ash loop.
  if [ "$CPU_BENCH_ONLY" != sh_loop ] && ! command -v dash >/dev/null 2>&1; then
    DASHAPK=""
    if ls "$HERE"/apks/dash-*.apk >/dev/null 2>&1; then
      DASHAPK=$(ls "$HERE"/apks/dash-*.apk | head -1)
    elif [ -f "$HERE/apks.tar" ]; then
      mkdir -p /tmp/cpu-benches-apks
      tar -C /tmp/cpu-benches-apks -xf "$HERE/apks.tar" ./dash-0.5.13.1-r2.apk 2>/dev/null ||         tar -C /tmp/cpu-benches-apks -xf "$HERE/apks.tar" dash-0.5.13.1-r2.apk 2>/dev/null || true
      if ls /tmp/cpu-benches-apks/dash-*.apk >/dev/null 2>&1; then
        DASHAPK=$(ls /tmp/cpu-benches-apks/dash-*.apk | head -1)
      fi
    fi
    if [ -n "$DASHAPK" ] && command -v apk >/dev/null 2>&1; then
      echo "======== install_dash ========"
      apk add --allow-untrusted --force-non-repository --no-network "$DASHAPK" || true
    fi
  fi
  if command -v dash >/dev/null 2>&1; then
    echo "DASH: $(command -v dash)"
    dash -c 'echo DASH_VERSION_OK'
  else
    echo "DASH: missing"
  fi
  if [ -z "$CPU_BENCH_ONLY" ] || [ "$CPU_BENCH_ONLY" = sh_loop ]; then
  if [ "$CPU_BENCH_ONLY" = sh_loop ]; then
    echo ===UML_JIT_PROFILE_RESET===
    sleep 1
  fi
  echo "SHELL_FOR_ASH_LOOP: $SH_FOR_LOOP"
  time_run sh_loop_ash "$SH_FOR_LOOP" -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'
  if command -v dash >/dev/null 2>&1 && [ "$CPU_BENCH_ONLY" != sh_loop ]; then
    time_run sh_loop_dash dash -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'
  fi
  if [ "$CPU_BENCH_ONLY" = sh_loop ]; then
    echo ===UML_JIT_PROFILE_DUMP===
    sleep 1
  fi
  fi
  if [ -z "$CPU_BENCH_ONLY" ]; then
  run dd_null dd if=/dev/zero of=/dev/null bs=1048576 count=32
  run dd_write32 dd if=/dev/zero of=/tmp/32m.bin bs=1048576 count=32
  time_run sha256_32m sha256sum /tmp/32m.bin

  fi
  if [ -z "$CPU_BENCH_ONLY" ] || [ "$CPU_BENCH_ONLY" = compile ]; then
  if command -v apk >/dev/null 2>&1; then
    # Prefer a pre-injected Alpine package pack so the guest does not need DNS.
    APKDIR=""
    if [ -d "$HERE/apks" ]; then
      APKDIR="$HERE/apks"
    elif [ -f "$HERE/apks.tar" ]; then
      mkdir -p /tmp/cpu-benches-apks
      tar -C /tmp/cpu-benches-apks -xf "$HERE/apks.tar"
      APKDIR=/tmp/cpu-benches-apks
    fi
    if [ -n "$APKDIR" ] && ls "$APKDIR"/*.apk >/dev/null 2>&1; then
      time_run apk_add_offline apk add --allow-untrusted --force-non-repository --no-network "$APKDIR"/*.apk
      echo "APK_OFFLINE_EXIT:$?"
      tree --version 2>/dev/null | head -1
      openssl version 2>/dev/null
      ${CC:-cc} --version 2>/dev/null | head -1 || true
    else
      time_run apk_add_tree apk add --no-cache tree
      echo "APK_TREE_EXIT:$?"
      tree --version 2>/dev/null | head -1
      time_run apk_add_openssl apk add --no-cache openssl
      echo "APK_OPENSSL_EXIT:$?"
      openssl version 2>/dev/null
      if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
        time_run apk_add_build_base apk add --no-cache build-base
        echo "APK_BUILD_BASE_EXIT:$?"
      fi
    fi
  else
    echo
    echo "======== apk_skipped (no apk on this host) ========"
  fi

  if [ -w /proc/sys/kernel/randomize_va_space ]; then
    echo "ASLR_BEFORE: $(cat /proc/sys/kernel/randomize_va_space)"
    echo 0 >/proc/sys/kernel/randomize_va_space
    echo "ASLR_AFTER: $(cat /proc/sys/kernel/randomize_va_space)"
  else
    echo "ASLR_UNAVAILABLE"
  fi
  if [ "$CPU_BENCH_ONLY" = compile ]; then
    if command -v dash >/dev/null 2>&1; then
      time_run sh_loop_dash dash -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'
    fi
    time_run sh_loop_ash "$SH_FOR_LOOP" -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'
    echo ===UML_JIT_PROFILE_RESET===
    sleep 1
  fi
  if [ -z "$CPU_BENCH_ONLY" ]; then
  if [ -x "$OPENSSL_BIN" ] || command -v "$OPENSSL_BIN" >/dev/null 2>&1; then
    run openssl_speed "$OPENSSL_BIN" speed -seconds 3 -evp sha256 aes-256-cbc
  fi

  fi
  fi
  if [ -z "$CPU_BENCH_ONLY" ] || [ "$CPU_BENCH_ONLY" = compile ]; then
  if [ -d "$TINY" ]; then
    work=/tmp/tiny-sha-build
    rm -rf "$work"
    mkdir -p "$work"
    cp "$TINY"/Makefile "$TINY"/*.c "$TINY"/*.h "$work"/
    echo
    echo "======== compile_tiny_sha ========"
    CC="${CC:-cc}"
    if command -v /usr/bin/time >/dev/null 2>&1; then
      /usr/bin/time -p sh -c "cd \"$work\" && make clean && make CC=$CC CFLAGS='-O2 -std=c11'"
    else
      sh -c "cd \"$work\" && make clean && make CC=$CC CFLAGS='-O2 -std=c11'"
    fi
    echo "COMPILE_EXIT:$?"
    if [ "$CPU_BENCH_ONLY" = compile ]; then
      echo ===UML_JIT_PROFILE_DUMP===
      echo ===UML_JIT_PROFILE_COLD===
      sleep 1
    fi
    if [ -x "$work/tiny-sha" ]; then
      if [ "$CPU_BENCH_ONLY" != compile ]; then
        time_run run_tiny_sha "$work/tiny-sha" 3
      fi
    else
      echo "tiny-sha binary missing"
    fi
    # Warm-cache second compile: same tree, make clean && make, after the
    # first gcc/cc1/as translations have been published.
    echo
    echo "======== compile_tiny_sha_warm ========"
    if command -v /usr/bin/time >/dev/null 2>&1; then
      /usr/bin/time -p sh -c "cd "$work" && make clean && make CC=$CC CFLAGS='-O2 -std=c11'"
    else
      sh -c "cd "$work" && make clean && make CC=$CC CFLAGS='-O2 -std=c11'"
    fi
    echo "COMPILE_WARM_EXIT:$?"
    LOOP="$HERE/native-loop/loop.c"
    if [ -f "$LOOP" ] && command -v "${CC:-cc}" >/dev/null 2>&1; then
      echo
      echo "======== compile_native_loop ========"
      if command -v /usr/bin/time >/dev/null 2>&1; then
        /usr/bin/time -p sh -c "${CC:-cc} -O2 -std=c11 -o /tmp/native-loop "$LOOP""
      else
        ${CC:-cc} -O2 -std=c11 -o /tmp/native-loop "$LOOP"
      fi
      echo "COMPILE_NATIVE_LOOP_EXIT:$?"
      if [ -x /tmp/native-loop ]; then
        time_run native_loop /tmp/native-loop
      fi
    else
      echo "native-loop skipped (no source or compiler)"
    fi
    if [ "$CPU_BENCH_ONLY" = compile ]; then
      echo ===UML_JIT_PROFILE_DUMP===
      sleep 1
    fi
  fi

  fi
  echo "===BENCH_DONE==="
  date
  echo "uptime: $(cat /proc/uptime 2>/dev/null || echo host)"
} 2>&1
