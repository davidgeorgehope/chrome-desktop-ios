// SPDX-License-Identifier: GPL-2.0-or-later

#include "jit_exit_profile.hpp"

#include "jit_shared_translations.hpp"

#include <array>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

namespace uml::cpu::arm64::jit_profile {
namespace {

std::atomic<bool> enabled_flag{false};
std::atomic<bool> initialized{false};
std::atomic<bool> stop_flusher{false};

std::atomic<std::uint64_t> run_blocks{0};
std::atomic<std::uint64_t> cache_hits{0};
std::atomic<std::uint64_t> cache_misses{0};
std::atomic<std::uint64_t> shared_reuses{0};
std::atomic<std::uint64_t> compiles{0};
std::atomic<std::uint64_t> compile_ns{0};
std::atomic<std::uint64_t> compile_instructions{0};
std::atomic<std::uint64_t> tracked_compiles{0};
std::atomic<std::uint64_t> tracked_compile_ns{0};
std::atomic<std::uint64_t> tracked_compile_instructions{0};

std::atomic<std::uint64_t> exit_svc{0};
std::atomic<std::uint64_t> exit_indirect_miss{0};
std::atomic<std::uint64_t> exit_page_fault{0};
std::atomic<std::uint64_t> exit_irq{0};
std::atomic<std::uint64_t> exit_continued{0};
std::atomic<std::uint64_t> exit_illegal{0};
std::atomic<std::uint64_t> exit_other{0};
std::atomic<std::uint64_t> retired_instructions{0};
std::array<std::atomic<std::uint64_t>,
           static_cast<std::size_t>(ContinuedReason::count)>
    continued_reasons{};
constexpr const char *continued_reason_names[] = {
    "uncompiled", "no_link", "unsafe", "inactive",
    "selector_store", "selector_fp", "fairness", "nonlink"};

std::mutex path_mutex;
std::string profile_path = "/tmp/uml-jit-profile.txt";
std::string control_path = "/tmp/uml-jit-profile.ctl";
std::once_flag start_flag;

[[nodiscard]] bool truthy_env(const char *value) noexcept {
  if (value == nullptr || value[0] == '\0')
    return false;
  return std::strcmp(value, "0") != 0 && std::strcmp(value, "false") != 0 &&
         std::strcmp(value, "FALSE") != 0 && std::strcmp(value, "off") != 0 &&
         std::strcmp(value, "OFF") != 0;
}

[[nodiscard]] bool looks_like_path(const char *value) noexcept {
  if (value == nullptr || value[0] == '\0')
    return false;
  if (value[0] == '/' || value[0] == '.')
    return true;
  return std::strchr(value, '/') != nullptr;
}

void write_report(std::FILE *out) noexcept {
  if (out == nullptr)
    return;
  const auto load = [](const std::atomic<std::uint64_t> &value) {
    return value.load(std::memory_order_relaxed);
  };
  const auto compiles_now = load(compiles);
  const auto compile_ns_now = load(compile_ns);
  const auto tracked_now = load(tracked_compiles);
  const auto tracked_ns_now = load(tracked_compile_ns);
  const auto shared = SharedTranslationCache::instance().statistics();
  std::fprintf(out, "===UML_JIT_PROFILE===\n");
  std::fprintf(out, "run_blocks=%llu\n",
               static_cast<unsigned long long>(load(run_blocks)));
  std::fprintf(out, "cache_hit=%llu\n",
               static_cast<unsigned long long>(load(cache_hits)));
  std::fprintf(out, "cache_miss=%llu\n",
               static_cast<unsigned long long>(load(cache_misses)));
  std::fprintf(out, "shared_reuse=%llu\n",
               static_cast<unsigned long long>(load(shared_reuses)));
  std::fprintf(out, "compiles=%llu\n",
               static_cast<unsigned long long>(compiles_now));
  std::fprintf(out, "compile_ns=%llu\n",
               static_cast<unsigned long long>(compile_ns_now));
  std::fprintf(out, "compile_ms=%.3f\n",
               static_cast<double>(compile_ns_now) / 1.0e6);
  std::fprintf(out, "compile_guest_insns=%llu\n",
               static_cast<unsigned long long>(load(compile_instructions)));
  std::fprintf(out, "avg_compile_us=%.3f\n",
               compiles_now == 0
                   ? 0.0
                   : (static_cast<double>(compile_ns_now) / 1.0e3) /
                         static_cast<double>(compiles_now));
  std::fprintf(out, "tracked_compiles=%llu\n",
               static_cast<unsigned long long>(tracked_now));
  std::fprintf(out, "tracked_compile_ns=%llu\n",
               static_cast<unsigned long long>(tracked_ns_now));
  std::fprintf(out, "tracked_compile_ms=%.3f\n",
               static_cast<double>(tracked_ns_now) / 1.0e6);
  std::fprintf(out, "tracked_compile_guest_insns=%llu\n",
               static_cast<unsigned long long>(
                   load(tracked_compile_instructions)));
  std::fprintf(out, "exit.svc=%llu\n",
               static_cast<unsigned long long>(load(exit_svc)));
  std::fprintf(out, "exit.indirect_miss=%llu\n",
               static_cast<unsigned long long>(load(exit_indirect_miss)));
  std::fprintf(out, "exit.page_fault=%llu\n",
               static_cast<unsigned long long>(load(exit_page_fault)));
  std::fprintf(out, "exit.irq=%llu\n",
               static_cast<unsigned long long>(load(exit_irq)));
  std::fprintf(out, "exit.continued=%llu\n",
               static_cast<unsigned long long>(load(exit_continued)));
  std::fprintf(out, "exit.illegal=%llu\n",
               static_cast<unsigned long long>(load(exit_illegal)));
  std::fprintf(out, "exit.other=%llu\n",
               static_cast<unsigned long long>(load(exit_other)));
  std::fprintf(out, "retired_insns=%llu\n",
               static_cast<unsigned long long>(load(retired_instructions)));
  for (std::size_t i = 0; i < continued_reasons.size(); ++i)
    std::fprintf(out, "exit.continued.%s=%llu\n", continued_reason_names[i],
                 static_cast<unsigned long long>(load(continued_reasons[i])));
  std::fprintf(out, "shared.matches=%llu\n",
               static_cast<unsigned long long>(shared.matches));
  std::fprintf(out, "shared.reuses=%llu\n",
               static_cast<unsigned long long>(shared.reuses));
  std::fprintf(out, "shared.misses=%llu\n",
               static_cast<unsigned long long>(shared.misses));
  std::fprintf(out, "shared.insertions=%llu\n",
               static_cast<unsigned long long>(shared.insertions));
  std::fprintf(out, "shared.evictions=%llu\n",
               static_cast<unsigned long long>(shared.evictions));
  std::fprintf(out, "shared.entries=%llu\n",
               static_cast<unsigned long long>(shared.entries));
  std::fprintf(out, "shared.rejected=%llu\n",
               static_cast<unsigned long long>(shared.rejected));
  std::fprintf(out, "shared.degraded_rejected=%llu\n",
               static_cast<unsigned long long>(shared.degraded_rejected));
  std::fprintf(out, "shared.malformed_rejected=%llu\n",
               static_cast<unsigned long long>(shared.malformed_rejected));
  std::fprintf(out, "shared.payload_bytes=%llu\n",
               static_cast<unsigned long long>(shared.payload_bytes));
  std::fprintf(out, "shared.accounted_bytes=%llu\n",
               static_cast<unsigned long long>(shared.accounted_bytes));
  std::fprintf(out, "shared.maximum_accounted_bytes=%llu\n",
               static_cast<unsigned long long>(shared.maximum_accounted_bytes));
  {
    static constexpr const char *reasons[] = {
        "null", "header", "identity_units", "guest_words", "hot_words",
        "entry_word", "link_meta", "write_mask", "reloc_count",
        "guest_write_mask", "reloc_kind", "reloc_slot", "reloc_nonzero",
        "reloc_alias", "isa", "shape_other"};
    const auto counts =
        SharedTranslationCache::instance().malformed_reasons();
    for (std::size_t index = 0; index < counts.size(); ++index)
      std::fprintf(out, "shared.malformed.%s=%llu\n", reasons[index],
                   static_cast<unsigned long long>(counts[index]));
  }
  std::fprintf(out, "===UML_JIT_PROFILE_END===\n");
  std::fflush(out);
}

void dump_to_file() noexcept {
  std::string path;
  {
    std::lock_guard<std::mutex> lock(path_mutex);
    path = profile_path;
  }
  if (path.empty())
    return;
  std::FILE *out = std::fopen(path.c_str(), "w");
  if (out == nullptr)
    return;
  write_report(out);
  std::fclose(out);
}

void reset_counters() noexcept {
  const auto zero = [](std::atomic<std::uint64_t> &value) {
    value.store(0, std::memory_order_relaxed);
  };
  zero(run_blocks);
  zero(cache_hits);
  zero(cache_misses);
  zero(shared_reuses);
  zero(compiles);
  zero(compile_ns);
  zero(compile_instructions);
  zero(tracked_compiles);
  zero(tracked_compile_ns);
  zero(tracked_compile_instructions);
  zero(exit_svc);
  zero(exit_indirect_miss);
  zero(exit_page_fault);
  zero(exit_irq);
  zero(exit_continued);
  zero(exit_illegal);
  zero(exit_other);
  zero(retired_instructions);
  for (auto &value : continued_reasons)
    zero(value);
}

void dump_final() noexcept {
  dump_to_file();
  write_report(stderr);
}

void poll_control() noexcept {
  std::string path;
  {
    std::lock_guard<std::mutex> lock(path_mutex);
    path = control_path;
  }
  if (path.empty())
    return;
  std::FILE *in = std::fopen(path.c_str(), "r");
  if (in == nullptr)
    return;
  char command[32]{};
  const auto n = std::fread(command, 1, sizeof(command) - 1U, in);
  std::fclose(in);
  std::remove(path.c_str());
  (void)n;
  if (std::strncmp(command, "reset", 5) == 0) {
    reset_counters();
    dump_to_file();
  } else if (std::strncmp(command, "dump", 4) == 0) {
    dump_final();
  }
}

void flusher_main() {
  while (!stop_flusher.load(std::memory_order_relaxed)) {
    poll_control();
    dump_to_file();
    for (int i = 0; i < 10 && !stop_flusher.load(std::memory_order_relaxed);
         ++i)
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  dump_final();
}

void start_flusher() {
  std::atexit([]() {
    stop_flusher.store(true, std::memory_order_relaxed);
    /* The detached flusher may still be in its 100 ms sleep. Give it a
     * moment, then write a last snapshot from this thread in case it has
     * already exited. */
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    dump_final();
  });
  std::thread{flusher_main}.detach();
}

void initialize() noexcept {
  bool expected = false;
  if (!initialized.compare_exchange_strong(expected, true,
                                           std::memory_order_acq_rel))
    return;
  const char *value = std::getenv("UML_JIT_PROFILE");
  if (!truthy_env(value))
    return;
  {
    std::lock_guard<std::mutex> lock(path_mutex);
    if (looks_like_path(value))
      profile_path = value;
    if (const char *file = std::getenv("UML_JIT_PROFILE_FILE");
        file != nullptr && file[0] != '\0')
      profile_path = file;
    if (const char *control = std::getenv("UML_JIT_PROFILE_CONTROL");
        control != nullptr && control[0] != '\0')
      control_path = control;
  }
  enabled_flag.store(true, std::memory_order_release);
  std::call_once(start_flag, start_flusher);
}

} // namespace

bool enabled() noexcept {
  if (!initialized.load(std::memory_order_acquire))
    initialize();
  return enabled_flag.load(std::memory_order_relaxed);
}

void record_run_block() noexcept {
  run_blocks.fetch_add(1, std::memory_order_relaxed);
}

void record_cache_hit() noexcept {
  cache_hits.fetch_add(1, std::memory_order_relaxed);
}

void record_cache_miss() noexcept {
  cache_misses.fetch_add(1, std::memory_order_relaxed);
}

void record_shared_reuse() noexcept {
  shared_reuses.fetch_add(1, std::memory_order_relaxed);
}

void record_compile(std::uint64_t nanoseconds,
                    std::size_t guest_instructions) noexcept {
  compiles.fetch_add(1, std::memory_order_relaxed);
  compile_ns.fetch_add(nanoseconds, std::memory_order_relaxed);
  compile_instructions.fetch_add(guest_instructions,
                                 std::memory_order_relaxed);
}

void record_tracked_compile(std::uint64_t nanoseconds,
                            std::size_t guest_instructions) noexcept {
  tracked_compiles.fetch_add(1, std::memory_order_relaxed);
  tracked_compile_ns.fetch_add(nanoseconds, std::memory_order_relaxed);
  tracked_compile_instructions.fetch_add(guest_instructions,
                                         std::memory_order_relaxed);
}

void record_block_exit(Event event, bool indirect_miss, bool irq) noexcept {
  if (irq || event == Event::interrupt) {
    exit_irq.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  if (event == Event::continued && indirect_miss) {
    exit_indirect_miss.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  switch (event) {
  case Event::system_call:
    exit_svc.fetch_add(1, std::memory_order_relaxed);
    break;
  case Event::memory_fault:
    exit_page_fault.fetch_add(1, std::memory_order_relaxed);
    break;
  case Event::continued:
    exit_continued.fetch_add(1, std::memory_order_relaxed);
    break;
  case Event::illegal_instruction:
    exit_illegal.fetch_add(1, std::memory_order_relaxed);
    break;
  default:
    exit_other.fetch_add(1, std::memory_order_relaxed);
    break;
  }
}

void record_continued_reason(ContinuedReason reason) noexcept {
  const auto index = static_cast<std::size_t>(reason);
  if (index < continued_reasons.size())
    continued_reasons[index].fetch_add(1, std::memory_order_relaxed);
}

void record_retired(std::uint64_t instructions) noexcept {
  retired_instructions.fetch_add(instructions, std::memory_order_relaxed);
}

void request_dump() noexcept { dump_final(); }

namespace {
std::once_flag dump_flag;
std::FILE *dump_file{};
std::mutex dump_mutex;
} // namespace

bool dump_enabled() noexcept {
  std::call_once(dump_flag, [] {
    const char *path = std::getenv("UML_JIT_DUMP");
    if (path != nullptr && path[0] != '\0')
      dump_file = std::fopen(path, "w");
  });
  return dump_file != nullptr;
}

void dump_block(std::uint64_t pc, const void *code,
                const std::uint32_t *guest, std::size_t guest_count,
                const std::uint32_t *host, std::size_t host_count,
                std::size_t hot_words) noexcept {
  if (!dump_enabled())
    return;
  std::lock_guard<std::mutex> lock(dump_mutex);
  std::fprintf(dump_file, "B %llx %llx %zu %zu %zu\nG",
               static_cast<unsigned long long>(pc),
               static_cast<unsigned long long>(
                   reinterpret_cast<std::uintptr_t>(code)),
               guest_count, host_count, hot_words);
  for (std::size_t i = 0; i < guest_count; ++i)
    std::fprintf(dump_file, " %08x", guest[i]);
  std::fprintf(dump_file, "\nH");
  for (std::size_t i = 0; i < host_count; ++i)
    std::fprintf(dump_file, " %08x", host[i]);
  std::fprintf(dump_file, "\n");
  std::fflush(dump_file);
}

} // namespace uml::cpu::arm64::jit_profile
