# Near pass-through execution (design)

Date: 13 Nov 2026, America/New_York. This is the design. A smallest
env-gated prototype was committed on `exclusive/0022-near-pass-through`
`8cfda0a` (5:36–5:38 PM ET); it is not landed on official 0022
(`uml-darwin` md5 `6ea8180e05fc6736d32530811ba3c439`). See NOTES.md
and the worktree's `notes/near-pass-through-prototype.md`.

The goal is a *usable desktop*: snappy app launch, scrolling, and typing.
Compile benches and time-to-example.com are necessary, but they are not
sufficient. A mode that copies guest ARM64 mostly verbatim, patches only
the instructions the host cannot run as-is, and maps guest user memory at
identity host addresses is the shortest path to that, because it removes
the two remaining per-instruction taxes: translation of ordinary
load/store/integer/SIMD, and the software TLB in front of already-mapped
RAM.

This is a different, stronger proposal than `DESIGN.md` (fixed-offset
`host_va = guest_va + K` with the existing translator still emitting
loads and stores). The 13 Nov `UML_JIT_USER_MAP=1` prototype was the
memory-side half of `DESIGN.md`. It booted and then *regressed* dash and
gcc, and is not landed. Near pass-through keeps the lesson (do not put a
bitmap or bounds check on every access) and changes the codegen: the
guest's own instruction stream is the generated code.

## What runs today

uml-darwin already has a fixed *physical* placement of guest RAM. A
Darwin native window (baseline `0x600000000000`, host-page aligned at
16 KiB) plus `direct-root=yes offset=41943040` means guest physical
address `PA` is host `window_base + offset + PA` with no second copy.
`StaticGuestMemory::translate` / `host_pointer` are how helpers and the
instruction-fetch path reach that mapping.

What generated code does *not* have is a fixed relationship between a
guest *virtual* address and a host address. Every translated load or
store still strips a top byte, walks the software TLB, falls back to the
static MMU, and only then issues a native access. Same-base unsigned
runs hoist some of that; pairs, signed offsets, and the general case do
not. SIGPROF of Firefox time-to-page on official 0022 (3:49–3:51 PM ET)
still showed the compile/memcpy/lock mix on the miss path; once a block
is in the L1, the remaining desktop tax is the translated memory
accesses themselves, plus exits for syscalls, system registers, and
exclusives.

The JIT is a proper translator: it decodes guest A64 (and A32), emits
host gadgets into a W^X arena, and links them. That is why ordinary
integer loops already run at ~1.3–1.5× host, and why compile and
first-content-process page load are dominated by *making* translations,
not by running them. For a desktop, the working set of libxul / Chromium
is huge, so first launch still compiles for tens of seconds. A verbatim
copy of a guest page is much cheaper than decode-and-emit of every
block, and the resulting code has no TLB sequence in front of
loads/stores *if* those addresses are already host-valid.

## The mode

1. **Copy guest ARM64 mostly verbatim.** For a translated block (or,
   more usefully, a whole guest page of EL0 A64), memcpy the instruction
   bytes into the existing JIT executable arena (the RX alias, written
   through the writable alias). Do not lower add/ldp/simd/fp to gadgets.
   Relocation of PC-relative literals is unnecessary if the copy is
   executed at a known offset and we patch only the instructions that
   cannot run as-is. A later, more aggressive variant executes the
   guest's own RAM in place; that is blocked by W^X on iOS and is not
   the first prototype.

2. **Patch only the instructions the host must intercept.**
   - `SVC` / `HVC` / `SMC` (and the A32 equivalents): exit to the UML
     syscall / exception path.
   - System-register access (`MRS`/`MSR`, `SYS`/`SYSL`, `IC`/`DC` that
     the helper must see, `HINT` forms that change PSTATE in ways the
     executor tracks).
   - Exclusives (`LDXR`/`STXR`/`LDAXR`/`STLXR` and pairs, `CLREX`):
     keep today's reservation / host-CAS path. Official 0022 already
     removed the process-wide exclusive-phase wait; a verbatim copy
     that ran raw `STXR` against identity-mapped RAM would still be
     wrong across vCPUs unless the reservation logic is preserved.
   - Anything else that reads or writes executor-private state the
     guest thinks is in-CPU (some `ISB`/`DSB` can be a host barrier;
     `ERET`, `BRK`, `SMC`, debug, SME mode-switch, and unallocated
     encodings exit).

   A linear decoder classifies each 4-byte A64 word as *copy*, *patch
   to a stub*, or *refuse the verbatim page and fall back to today's
   translator*. A32/T32, JIT-unsafe self-modifying regions, and
   instruction pages that are also written stay on the existing path.

3. **Map guest user memory at identity host addresses.** The UML
   process *is* the guest address space for EL0: `host_va == guest_va`
   (`K = 0`), not `guest_va + K` with a bitmap. Then the copied
   `LDR`/`STR`/`LDP` need no prefix, no TLB, and no bounds check.
   Demand-zero and file-backed pages are installed at the guest VA on
   the first fault, with the guest's permissions, as a second mapping
   of the same native-window VM object already used for physical RAM.
   The guest kernel high half stays on the physical window.

This is the classical UML trick, adapted to a Darwin process that
already has a native window, a MAP_JIT arena, and a 16 KiB host page.

## Why the 13 Nov user-map prototype is not this

`DESIGN.md` proposed `host = guest_va + K` and kept the translator.
The prototype reserved a compact pack of 32 × 32 GiB slots, remapped
uniform 16 KiB spans with `vm_remap`, and emitted `guest_va + K` plus
a per-access installed-page bitmap. Identity at musl PIE addresses
(`0x7fff…`, just below the 47-bit guest limit) was not mmapable at
the sizes tried; slot 0's `K` was a wrap (`0xffffe01000000000`), not
zero. The bitmap and fallback to the software TLB cost more than they
saved: dash 0.18 s → 0.28–0.30 s, warm compile 1.15–1.16 s → 1.33–1.46 s,
on both 4K and 16K guests. A 16 KiB guest `PAGE_SIZE` removes the
4-into-1 mixed-span problem but did not rescue the flag.

Near pass-through therefore has two non-negotiable rules:

- No per-access bitmap or bounds check on the fast path. If a page is
  not installed at identity, the host CPU takes a fault and the handler
  installs or delivers a guest fault. The copied instruction itself is
  the access.
- Prefer a 16 KiB guest page so one guest page is one Darwin host page.
  A 4 KiB guest on a 16 KiB host cannot install a single 4 KiB
  permission without sharing a host page with its neighbours; that is
  what forced the bitmap. The 16K kernel work is still experimental
  (see `DESIGN.md`) and is a dependency for a *complete* identity map,
  not for a first verbatim-codegen prototype that still uses the
  software TLB.

## iOS blockers

macOS uml-darwin is the only reasonable first host. iOS (Designed-for-iPad,
Simulator, and a real device) has three structural blockers. They need
honest answers before this mode is promised on a phone or iPad.

### JIT W^X

iOS will not execute writable memory. Guest RAM is an ordinary RW
mapping. A verbatim copy must be written through the existing writable
JIT alias and executed from the RX alias (`pthread_jit_write_protect_np`
/ the newer thread-restrict APIs, `MAP_JIT`, the JIT entitlement).
Executing in place from an identity-mapped guest page is a
code-signing kill, not a fast path.

The current D4iPad path already needs an Aqua LaunchAgent plus lldb
`jit_serve` to prepare a large cache. A mode that copies whole code
pages will *increase* writable-alias traffic; it must still toggle
W^X per page (or per batch), not per instruction, or the toggle becomes
the new tax. The Simulator is looser than a device; a prototype that
only works in the Simulator is not an iOS result.

### Address-space reservation

Identity means the host process must own the guest's user VA. On the
Mac mini, `mach_vm_region` shows huge holes around the native window,
but a 1 TiB `MAP_NORESERVE` already failed with `ENOMEM`. A contiguous
TASK_SIZE (2^39–2^48) alias does not fit beside the native window, the
MAP_JIT arena, and ordinary host allocations. iOS is tighter: the app's
own ASLR, the shared region, and a much smaller usable VA make a
47-bit identity reservation even less likely than on macOS.

A practical compromise, if identity of the full musl PIE range cannot
be reserved, is to *force the guest user layout* into a window the host
*can* reserve (ASLR off, or a guest-side allocator constraint), and
make that window identity (`K = 0` at a base the host actually owns).
That is still "no add, no check" for addresses in the window. It is
not a process-global map of 2^47 bytes, and two guest mm's still must
not alias the same host VA (per-mm slots, or a single desktop mm).

### Signals and page faults

The "no checks" fast path *is* a SIGSEGV/SIGBUS (or Mach exception)
handler: first touch, permission change, CoW, and genuine guest faults
all arrive as host faults on the identity address. Completing a guest
fault from a signal handler while a vCPU is inside copied guest code
is the hard part. The user-map prototype already had to keep
exclusives, atomics, and straddles on the TLB path because the handler
could not safely finish an access that had been rewritten to `guest+K`
for an unmapped or mixed page.

On iOS the same handler is more hostile: a SIGSEGV in a JIT region, a
W^X violation, or a code-signing fault can kill the process instead of
delivering a POSIX signal. Jetsam may also kill a 4 GiB guest plus an
identity reservation under memory pressure. The prototype must prove
the fault path on macOS (including a deliberate munmap under a spinning
load/store, and a CoW fork) before it is ported.

## Rough prototype plan

Work on a side branch of Kernarium, measured against official 0022.
Do not overwrite official binaries. Land only if interactive metrics
and the existing compile / TTP / atomic-stress bar all improve, with
no RCU-stall hangs of the kind seen on one fetch-view Firefox run.

1. **Classifier and verbatim emitter (macOS, today's 4K guest, software
   TLB still on).** Decode a block or a 4K/16K instruction page, copy
   the *copy* class into the JIT arena, patch SVC / sysreg / exclusive
   to existing exits. Execute with the current memory lowering still in
   front of any load/store that the classifier did not leave raw (at
   this step: all of them, if we have not yet identity-mapped). Measure
   compile-cold and Firefox TTP: the win, if any, is cheaper
   translation, not faster loops. Keep a fallback to today's compiler
   for A32 and for pages that fail the classifier.

2. **Forced-window or identity user map, 16K guest first.** Reuse the
   reservation inventory from the user-map work, but aim for `K = 0` in
   a window the guest is actually forced to use, with one host page per
   guest page and *no* per-access bitmap. Leave kernel VAs on the
   physical window. Prove mmap/mprotect/munmap/CoW against unit tests
   and atomic-stress.

3. **Leave loads and stores verbatim** once a page is installed at
   identity. Faults install or become guest faults. Exclusives still
   detour. Re-measure openssl evp, tiny-sha, dash, and the tight loop;
   the user-map flag must not be repeated: any regression vs 0022
   flag-off on those walls stops the prototype.

4. **Interactive metrics, not just TTP.** Run
   `scripts/macos-metal/measure-interactive.sh` (app launch, scroll
   fps, input latency) against official 0022 and the prototype on the
   same labwc image. A compile win that leaves scroll at 15 fps or
   typing lagged is not a desktop win.

5. **Reliability.** Repeat Firefox and Chromium TTP ×2 at
   memory-pressure preflight. A single RCU-stall hang that leaves the
   page transferring forever is a no-land, even if the other run looks
   faster.

6. **iOS only after macOS is a clear win.** Walk W^X (copy into the RX
   arena in batches), the reservation that D4iPad and the Simulator can
   actually get, and the fault handler under iOS exception delivery.
   Physical iPhone/iPad installs stay out of scope until that is
   written down with measurements.

## Related

- `DESIGN.md` — fixed-offset `guest_va + K`, user-map prototype, 16K
  guest page experiment.
- `NOTES.md` — 12 Nov JIT near-pass-through CPU profile; 13 Nov
  exclusive-phase 0022 land; fetch-view experiment (not landed); this
  design's measurement bar.
- `scripts/macos-metal/measure-interactive.sh` and
  `scripts/desktop-guest/interactive-metrics/` — app launch, scroll
  fps, input latency.
