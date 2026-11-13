// SPDX-License-Identifier: GPL-2.0-or-later
#include "jit_sigprof.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <mutex>
#include <signal.h>
#include <string>
#include <sys/time.h>
#include <sys/ucontext.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace uml::cpu::arm64::jit::sigprof {
namespace {

constexpr std::size_t table_size = 4096;
constexpr std::size_t max_ranges = 32;

struct Slot {
  std::atomic<std::uintptr_t> pc{0};
  std::atomic<std::uint64_t> count{0};
};

struct Range {
  std::uintptr_t base{};
  std::uintptr_t end{};
  const char *name{};
};

std::array<Slot, table_size> table{};
std::atomic<std::uint64_t> samples{0};
std::atomic<std::uint64_t> dropped{0};
std::atomic<bool> armed{false};
std::atomic<bool> enabled_flag{false};
std::atomic<bool> stop_flusher{false};
std::atomic<bool> dumped{false};
std::once_flag start_flag;
std::string dump_path;
std::mutex path_mutex;
std::mutex dump_mutex;
std::array<Range, max_ranges> ranges{};
std::atomic<std::size_t> range_count{0};

[[nodiscard]] bool truthy_env(const char *value) noexcept {
  if (value == nullptr || value[0] == '\0')
    return false;
  return std::strcmp(value, "0") != 0 && std::strcmp(value, "false") != 0 &&
         std::strcmp(value, "off") != 0;
}

[[nodiscard]] bool looks_like_path(const char *value) noexcept {
  return value != nullptr &&
         (value[0] == '/' || value[0] == '.' || std::strchr(value, '/') != nullptr);
}

[[nodiscard]] unsigned parse_hz(const char *value) noexcept {
  if (value == nullptr || value[0] == '\0')
    return 99;
  char *end = nullptr;
  const long parsed = std::strtol(value, &end, 10);
  if (end == value || parsed < 1 || parsed > 1000)
    return 99;
  return static_cast<unsigned>(parsed);
}

void handle_sigprof(int, siginfo_t *, void *context) noexcept {
  auto *uc = static_cast<ucontext_t *>(context);
  std::uintptr_t pc = 0;
  if (uc != nullptr) {
#if defined(__arm64__) || defined(__aarch64__)
    pc = static_cast<std::uintptr_t>(uc->uc_mcontext->__ss.__pc);
#elif defined(__x86_64__)
    pc = static_cast<std::uintptr_t>(uc->uc_mcontext->__ss.__rip);
#endif
  }
  samples.fetch_add(1, std::memory_order_relaxed);
  if (pc == 0) {
    dropped.fetch_add(1, std::memory_order_relaxed);
    return;
  }
  auto hash = static_cast<std::size_t>(pc >> 2);
  for (std::size_t probe = 0; probe < 16; ++probe) {
    auto &slot = table[(hash + probe) & (table_size - 1U)];
    auto observed = slot.pc.load(std::memory_order_relaxed);
    if (observed == 0) {
      std::uintptr_t expected = 0;
      if (slot.pc.compare_exchange_strong(expected, pc,
                                          std::memory_order_relaxed)) {
        slot.count.fetch_add(1, std::memory_order_relaxed);
        return;
      }
      observed = expected;
    }
    if (observed == pc) {
      slot.count.fetch_add(1, std::memory_order_relaxed);
      return;
    }
  }
  dropped.fetch_add(1, std::memory_order_relaxed);
}

void install_handler(unsigned hz) {
  struct sigaction action {};
  action.sa_sigaction = handle_sigprof;
  action.sa_flags = SA_RESTART | SA_SIGINFO;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGPROF, &action, nullptr) != 0)
    return;
  struct itimerval timer {};
  const auto usec = 1000000L / static_cast<long>(hz);
  timer.it_interval.tv_usec = usec;
  timer.it_value.tv_usec = usec;
  if (setitimer(ITIMER_PROF, &timer, nullptr) != 0)
    return;
  armed.store(true, std::memory_order_release);
}

void stop_timer() noexcept {
  if (!armed.load(std::memory_order_acquire))
    return;
  struct itimerval timer {};
  setitimer(ITIMER_PROF, &timer, nullptr);
  armed.store(false, std::memory_order_release);
}

[[nodiscard]] const Range *range_for(std::uintptr_t pc) noexcept {
  const auto n = range_count.load(std::memory_order_acquire);
  for (std::size_t i = 0; i < n && i < max_ranges; ++i) {
    if (pc >= ranges[i].base && pc < ranges[i].end)
      return &ranges[i];
  }
  return nullptr;
}

void dump_to_stream() noexcept;

void dump_now() noexcept {
  std::lock_guard<std::mutex> lock(dump_mutex);
  dump_to_stream();
}

void flusher_main() {
  while (!stop_flusher.load(std::memory_order_relaxed)) {
    dump_now();
    for (int i = 0; i < 10 && !stop_flusher.load(std::memory_order_relaxed);
         ++i)
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  dump_now();
}

void start_flusher() {
  std::thread{flusher_main}.detach();
}

void stop_flusher_thread() noexcept {
  stop_flusher.store(true, std::memory_order_relaxed);
}

void dump_to_stream() noexcept {
  if (!enabled_flag.load(std::memory_order_relaxed))
    return;
  struct Row {
    std::uintptr_t pc;
    std::uint64_t count;
  };
  std::vector<Row> rows;
  rows.reserve(256);
  for (auto &slot : table) {
    const auto pc = slot.pc.load(std::memory_order_relaxed);
    const auto count = slot.count.load(std::memory_order_relaxed);
    if (pc != 0 && count != 0)
      rows.push_back({pc, count});
  }
  std::sort(rows.begin(), rows.end(),
            [](const Row &a, const Row &b) { return a.count > b.count; });

  std::string path;
  {
    std::lock_guard<std::mutex> lock(path_mutex);
    path = dump_path;
  }
  std::FILE *out = stderr;
  std::FILE *owned = nullptr;
  if (!path.empty() && path != "-") {
    owned = std::fopen(path.c_str(), "w");
    if (owned != nullptr)
      out = owned;
  }
  const auto total = samples.load(std::memory_order_relaxed);
  const auto lost = dropped.load(std::memory_order_relaxed);
  std::fprintf(out, "===UML_JIT_SIGPROF===\n");
  std::fprintf(out, "samples=%llu dropped=%llu unique=%zu\n",
               static_cast<unsigned long long>(total),
               static_cast<unsigned long long>(lost), rows.size());
  for (const auto &row : rows) {
    const auto *range = range_for(row.pc);
    Dl_info info{};
    const char *symbol = nullptr;
    const char *module = nullptr;
    std::uintptr_t symbol_base = 0;
    if (range != nullptr) {
      symbol = range->name;
      symbol_base = range->base;
    } else if (dladdr(reinterpret_cast<const void *>(row.pc), &info) != 0) {
      symbol = info.dli_sname != nullptr ? info.dli_sname : info.dli_fname;
      module = info.dli_fname;
      symbol_base = reinterpret_cast<std::uintptr_t>(
          info.dli_saddr != nullptr ? info.dli_saddr : info.dli_fbase);
    }
    std::fprintf(out, "%8llu  0x%llx",
                 static_cast<unsigned long long>(row.count),
                 static_cast<unsigned long long>(row.pc));
    if (symbol != nullptr) {
      std::fprintf(out, "  %s+0x%llx", symbol,
                   static_cast<unsigned long long>(row.pc - symbol_base));
      if (module != nullptr && range == nullptr)
        std::fprintf(out, "  (%s)", module);
    }
    std::fputc('\n', out);
  }
  std::fprintf(out, "===UML_JIT_SIGPROF_END===\n");
  if (owned != nullptr)
    std::fclose(owned);
}

} // namespace

void on_process_exit() noexcept;

void initialize() noexcept {
  std::call_once(start_flag, [] {
    const char *value = std::getenv("UML_JIT_SIGPROF");
    if (!truthy_env(value))
      return;
    unsigned hz = parse_hz(std::getenv("UML_JIT_SIGPROF_HZ"));
    {
      std::lock_guard<std::mutex> lock(path_mutex);
      if (looks_like_path(value))
        dump_path = value;
      if (const char *file = std::getenv("UML_JIT_SIGPROF_FILE");
          file != nullptr && file[0] != '\0')
        dump_path = file;
      if (dump_path.empty())
        dump_path = "-";
    }
    enabled_flag.store(true, std::memory_order_release);
    install_handler(hz);
    if (armed.load(std::memory_order_acquire)) {
      std::string path;
      {
        std::lock_guard<std::mutex> lock(path_mutex);
        path = dump_path;
      }
      std::fprintf(stderr, "UML_JIT_SIGPROF armed hz=%u file=%s\n", hz,
                   path.c_str());
      if (!path.empty() && path != "-")
        start_flusher();
    } else {
      std::fprintf(stderr, "UML_JIT_SIGPROF failed to arm timer\n");
    }
    std::atexit([] {
      on_process_exit();
    });
  });
}

void shutdown() noexcept { stop_timer(); }

void dump() noexcept {
  if (!enabled_flag.load(std::memory_order_relaxed))
    return;
  dump_now();
  dumped.store(true, std::memory_order_relaxed);
}

bool enabled() noexcept {
  initialize();
  return enabled_flag.load(std::memory_order_relaxed);
}

void register_code_range(const void *base, std::size_t bytes,
                         const char *name) noexcept {
  if (base == nullptr || bytes == 0)
    return;
  auto index = range_count.load(std::memory_order_relaxed);
  while (index < max_ranges) {
    if (range_count.compare_exchange_weak(index, index + 1,
                                          std::memory_order_acq_rel,
                                          std::memory_order_relaxed)) {
      ranges[index] = {reinterpret_cast<std::uintptr_t>(base),
                       reinterpret_cast<std::uintptr_t>(base) + bytes,
                       name != nullptr ? name : "jit"};
      return;
    }
  }
}

void on_process_exit() noexcept {
  stop_flusher_thread();
  shutdown();
  dump();
}

} // namespace uml::cpu::arm64::jit::sigprof

extern "C" void uml_jit_sigprof_on_exit(void) {
  uml::cpu::arm64::jit::sigprof::on_process_exit();
}

namespace {

[[maybe_unused]] const auto sigprof_boot = [] {
  uml::cpu::arm64::jit::sigprof::initialize();
  return 0;
}();

} // namespace
