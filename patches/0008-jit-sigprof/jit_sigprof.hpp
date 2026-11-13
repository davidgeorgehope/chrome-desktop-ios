// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <cstddef>
#include <cstdint>

/*
 * Cheap in-process SIGPROF host-PC histogram for uml-darwin.
 *
 * dtrace and sample are unavailable on the bakeoff mini (SIP / no timeout /
 * TCC). This sampler is independent of UML_JIT_PROFILE. Set UML_JIT_SIGPROF
 * to 1 or a dump path, optionally UML_JIT_SIGPROF_FILE and UML_JIT_SIGPROF_HZ
 * (default 99). The handler only bumps preallocated atomics; symbolization
 * happens at dump time.
 */
namespace uml::cpu::arm64::jit::sigprof {

void initialize() noexcept;
void shutdown() noexcept;
void dump() noexcept;
[[nodiscard]] bool enabled() noexcept;

/* Optional: name a generated-code range so unsigned PCs dump as jit+offset
 * instead of a raw address. Safe to call repeatedly; later ranges append. */
void register_code_range(const void *base, std::size_t bytes,
                         const char *name) noexcept;

} // namespace uml::cpu::arm64::jit::sigprof

#ifdef __cplusplus
extern "C" {
#endif
/* Safe to call from darwin_uml_exit() before _exit(), which skips atexit. */
void uml_jit_sigprof_on_exit(void);
#ifdef __cplusplus
}
#endif
