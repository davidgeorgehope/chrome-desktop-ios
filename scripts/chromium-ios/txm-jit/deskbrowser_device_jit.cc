// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifdef UNSAFE_BUFFERS_BUILD
// TODO(deskbrowser): convert the prepared-region table to base::span.
#pragma allow_unsafe_buffers
#endif

#include "content/app/ios/deskbrowser_device_jit.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/vm_map.h>
#include <stdint.h>
#include <signal.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <unistd.h>

#include <pthread.h>

#include <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR && TARGET_OS_IOS

// CS_OPS_STATUS / CS_DEBUGGED. Declared locally so we do not depend on
// the private codesign header. syscall 169 is SYS_csops on Darwin.
#ifndef SYS_csops
#define SYS_csops 169
#endif
#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000u
#endif

extern "C" void* DeskBrowserJit26PrepareRegion(void* address, size_t length);
extern "C" void DeskBrowserJit26Detach(void);
extern "C" int syscall(int, ...);

namespace {

constexpr size_t kIosPage = 16384;

struct Region {
  uintptr_t rx = 0;
  uintptr_t rw = 0;
  size_t size = 0;
};

pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
Region g_regions[32];
int g_nregions = 0;
bool g_enabled = false;
bool g_handler_installed = false;
struct sigaction g_prev_sigtrap {};
thread_local bool g_expecting_trap = false;

size_t PageAlign(size_t n) {
  return (n + (kIosPage - 1)) & ~(kIosPage - 1);
}

void Log(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "deskbrowser-jit: ");
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
}

bool IsDebugged() {
  uint32_t flags = 0;
  // Ask the kernel directly (libc csops can be hooked on jailbreaks).
  if (syscall(SYS_csops, getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0) {
    return false;
  }
  return (flags & CS_DEBUGGED) != 0;
}

void TrapHandler(int sig, siginfo_t* info, void* ctx_void) {
  if (!g_expecting_trap) {
    struct sigaction* prev = &g_prev_sigtrap;
    if (prev->sa_flags & SA_SIGINFO) {
      prev->sa_sigaction(sig, info, ctx_void);
    } else if (prev->sa_handler == SIG_IGN) {
      return;
    } else if (prev->sa_handler == SIG_DFL) {
      signal(sig, SIG_DFL);
      raise(sig);
    } else {
      prev->sa_handler(sig);
    }
    return;
  }
  // Skip the brk (4 bytes) and return 0 in x0 so an unserviced
  // prepare becomes a failed call instead of process death.
  ucontext_t* uc = static_cast<ucontext_t*>(ctx_void);
  uc->uc_mcontext->__ss.__pc += 4;
  uc->uc_mcontext->__ss.__x[0] = 0;
}

uintptr_t CreateRwAlias(uintptr_t rx, size_t size) {
  vm_address_t alias = 0;
  vm_prot_t cur = 0, max = 0;
  kern_return_t kr =
      vm_remap(mach_task_self(), &alias, size, 0, VM_FLAGS_ANYWHERE,
               mach_task_self(), static_cast<vm_address_t>(rx), FALSE, &cur,
               &max, VM_INHERIT_NONE);
  if (kr != KERN_SUCCESS) {
    Log("vm_remap failed: %s", mach_error_string(kr));
    return 0;
  }
  if (vm_protect(mach_task_self(), alias, size, FALSE,
                 VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS) {
    Log("vm_protect RW failed");
    vm_deallocate(mach_task_self(), alias, size);
    return 0;
  }
  return static_cast<uintptr_t>(alias);
}

}  // namespace

extern "C" void DeskBrowserJitInstallTrapHandler(void) {
  if (g_handler_installed) {
    return;
  }
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = TrapHandler;
  sa.sa_flags = SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGTRAP, &sa, &g_prev_sigtrap);
  g_handler_installed = true;
}

extern "C" bool DeskBrowserJitTryEnable(void) {
  DeskBrowserJitInstallTrapHandler();
  if (!IsDebugged()) {
    Log("no CS_DEBUGGED; staying jitless. Attach StikDebug (universal.js) "
        "to com.davidhope.deskbrowser.blink, then relaunch.");
    return false;
  }
  g_enabled = true;
  Log("CS_DEBUGGED set; TXM prepare hook enabled (debugger will stay attached)");
  return true;
}

extern "C" bool DeskBrowserJitIsEnabled(void) { return g_enabled; }

extern "C" void DeskBrowserJitPrepareRegion(void* addr, size_t size) {
  if (!g_enabled || !addr || size == 0) {
    return;
  }
  uintptr_t rx = reinterpret_cast<uintptr_t>(addr);
  size = PageAlign(size);
  pthread_mutex_lock(&g_mu);
  for (int i = 0; i < g_nregions; ++i) {
    const Region& r = g_regions[i];
    if (rx >= r.rx && rx + size <= r.rx + r.size) {
      pthread_mutex_unlock(&g_mu);
      return;
    }
  }
  pthread_mutex_unlock(&g_mu);
  if (!IsDebugged()) {
    Log("prepare skipped: debugger no longer attached");
    return;
  }
  g_expecting_trap = true;
  void* prepared = DeskBrowserJit26PrepareRegion(reinterpret_cast<void*>(rx),
                                                 size);
  g_expecting_trap = false;
  if (!prepared) {
    Log("JIT26PrepareRegion failed for %p+%zu", addr, size);
    return;
  }
  // The script may return a new address; prefer the prepared mapping.
  uintptr_t prepared_rx = reinterpret_cast<uintptr_t>(prepared);
  if (prepared_rx != 0) {
    rx = prepared_rx;
  }
  uintptr_t rw = CreateRwAlias(rx, size);
  if (!rw) {
    return;
  }
  pthread_mutex_lock(&g_mu);
  if (g_nregions < static_cast<int>(sizeof(g_regions) / sizeof(g_regions[0]))) {
    g_regions[g_nregions++] = Region{rx, rw, size};
    Log("prepared RX %p RW %p size %zu", reinterpret_cast<void*>(rx),
        reinterpret_cast<void*>(rw), size);
  } else {
    Log("too many prepared regions");
    vm_deallocate(mach_task_self(), static_cast<vm_address_t>(rw), size);
  }
  pthread_mutex_unlock(&g_mu);
}

extern "C" void* DeskBrowserJitWritableAddr(const void* addr) {
  if (!addr || !g_enabled) {
    return const_cast<void*>(addr);
  }
  uintptr_t p = reinterpret_cast<uintptr_t>(addr);
  pthread_mutex_lock(&g_mu);
  for (int i = 0; i < g_nregions; ++i) {
    const Region& r = g_regions[i];
    if (p >= r.rx && p < r.rx + r.size) {
      void* out = reinterpret_cast<void*>(r.rw + (p - r.rx));
      pthread_mutex_unlock(&g_mu);
      return out;
    }
  }
  pthread_mutex_unlock(&g_mu);
  return const_cast<void*>(addr);
}

extern "C" void DeskBrowserJitReleaseRegion(void* addr, size_t size) {
  if (!addr) {
    return;
  }
  uintptr_t rx = reinterpret_cast<uintptr_t>(addr);
  size_t aligned = PageAlign(size);
  pthread_mutex_lock(&g_mu);
  for (int i = 0; i < g_nregions; ++i) {
    if (g_regions[i].rx == rx && g_regions[i].size == aligned) {
      vm_deallocate(mach_task_self(),
                    static_cast<vm_address_t>(g_regions[i].rw),
                    g_regions[i].size);
      g_regions[i] = g_regions[g_nregions - 1];
      --g_nregions;
      break;
    }
  }
  pthread_mutex_unlock(&g_mu);
}

#else  // simulator / tvOS

extern "C" void DeskBrowserJitInstallTrapHandler(void) {}
extern "C" bool DeskBrowserJitTryEnable(void) { return false; }
extern "C" bool DeskBrowserJitIsEnabled(void) { return false; }
extern "C" void DeskBrowserJitPrepareRegion(void*, size_t) {}
extern "C" void* DeskBrowserJitWritableAddr(const void* addr) {
  return const_cast<void*>(addr);
}
extern "C" void DeskBrowserJitReleaseRegion(void*, size_t) {}

#endif
