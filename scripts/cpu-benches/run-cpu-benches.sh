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
  time_run sh_loop "$SH_FOR_LOOP" -c 'i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done'
  run dd_null dd if=/dev/zero of=/dev/null bs=1048576 count=32
  run dd_write32 dd if=/dev/zero of=/tmp/32m.bin bs=1048576 count=32
  time_run sha256_32m sha256sum /tmp/32m.bin

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

  if [ -x "$OPENSSL_BIN" ] || command -v "$OPENSSL_BIN" >/dev/null 2>&1; then
    run openssl_speed "$OPENSSL_BIN" speed -seconds 3 -evp sha256 aes-256-cbc
  fi

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
    if [ -x "$work/tiny-sha" ]; then
      time_run run_tiny_sha "$work/tiny-sha" 3
    else
      echo "tiny-sha binary missing"
    fi
  fi

  echo "===BENCH_DONE==="
  date
  echo "uptime: $(cat /proc/uptime 2>/dev/null || echo host)"
} 2>&1
