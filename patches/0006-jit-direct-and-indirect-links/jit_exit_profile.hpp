// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "jit_runtime_contract.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>

namespace uml::cpu::arm64::jit_profile {

/* Cheap, default-off translated-block exit profiler.
 *
 * Enable with UML_JIT_PROFILE=1 (or any value other than 0/false/off). If the
 * value looks like a path, counters are also written there. UML_JIT_PROFILE_FILE
 * overrides the path; the default file is /tmp/uml-jit-profile.txt. A flusher
 * rewrites that file about once a second, and a final dump goes to stderr
 * when the host process exits.
 *
 * The disabled path is one predictable branch on each run_block entry and
 * exit. Compile timing and shared-cache statistics are recorded only when
 * the profiler is on.
 */
[[nodiscard]] bool enabled() noexcept;

void record_run_block() noexcept;
void record_cache_hit() noexcept;
void record_cache_miss() noexcept;
void record_shared_reuse() noexcept;
void record_compile(std::uint64_t nanoseconds,
                    std::size_t guest_instructions) noexcept;
void record_tracked_compile(std::uint64_t nanoseconds,
                            std::size_t guest_instructions) noexcept;
void record_block_exit(Event event, bool indirect_miss, bool irq) noexcept;
/* Why a translated chain returned Event::continued without an indirect miss,
 * classified in C++ from the state of the block at the exit PC. */
enum class ContinuedReason : unsigned {
  uncompiled,      // no current translation at the exit PC (unlinked direct)
  no_link,         // target has no link record
  unsafe,          // target is not a link target (reservation split)
  inactive,        // target link not activated in this epoch / no entry
  selector_store,  // chain selector lacks store publication the target needs
  selector_fp,     // chain selector lacks FP state the target needs
  fairness,        // the 4096-instruction budget ran out
  nonlink,         // a linkable target was fine: the exit was not a link
  count,
};
void record_continued_reason(ContinuedReason reason) noexcept;
void record_retired(std::uint64_t instructions) noexcept;
void request_dump() noexcept;

class RunScope final {
public:
  RunScope() noexcept {
    if (enabled())
      record_run_block();
  }
  RunScope(const RunScope &) = delete;
  RunScope &operator=(const RunScope &) = delete;

  Event finish(Event event) noexcept {
    event_ = event;
    armed_ = true;
    return event;
  }

  Event finish_irq(Event event) noexcept {
    irq_ = true;
    return finish(event);
  }

  void note_indirect_miss() noexcept { indirect_ = true; }

  void note_cache_hit() noexcept {
    if (enabled())
      record_cache_hit();
  }

  void note_cache_miss() noexcept {
    if (enabled())
      record_cache_miss();
  }

  void note_shared_reuse() noexcept {
    if (enabled())
      record_shared_reuse();
  }

  ~RunScope() noexcept {
    if (armed_ && enabled())
      record_block_exit(event_, indirect_, irq_);
  }

private:
  Event event_{Event::fatal};
  bool armed_{false};
  bool irq_{false};
  bool indirect_{false};
};

class CompileTimer final {
public:
  explicit CompileTimer(bool tracked = false) noexcept
      : on_(enabled()), tracked_(tracked) {
    if (on_)
      start_ = std::chrono::steady_clock::now();
  }
  CompileTimer(const CompileTimer &) = delete;
  CompileTimer &operator=(const CompileTimer &) = delete;

  void complete(std::size_t guest_instructions) noexcept {
    if (!on_ || completed_)
      return;
    completed_ = true;
    const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
                        std::chrono::steady_clock::now() - start_)
                        .count();
    const auto elapsed = static_cast<std::uint64_t>(ns < 0 ? 0 : ns);
    if (tracked_)
      record_tracked_compile(elapsed, guest_instructions);
    else
      record_compile(elapsed, guest_instructions);
  }

  ~CompileTimer() noexcept {
    if (!completed_)
      complete(0);
  }

private:
  std::chrono::steady_clock::time_point start_{};
  bool on_{false};
  bool tracked_{false};
  bool completed_{false};
};

} // namespace uml::cpu::arm64::jit_profile
