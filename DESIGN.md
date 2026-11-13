# Fixed-offset guest user memory mapping

This is a design only. It has not been implemented. It is the memory-side
follow-on to the 12 Nov 2026 JIT CPU profile (`scripts/cpu-benches/RESULTS.md`).
The memory tax on already-translated software (openssl evp ~1.5×, gcc-built
tiny-sha ~1.88×) is smaller than the shell and compile multipliers, but a
fixed-offset map is also what would make translations reusable across `exec`.

## What the JIT does today

Guest RAM already has a fixed *physical* placement on the host. uml-darwin
reserves a Darwin native window (on the 12 Nov 2026 baseline,
`0x600000000000-0x60014000c000`, host-page aligned at 16 KiB) and, with
`direct-root=yes offset=41943040`, maps guest physical pages as a sparse
suffix of that window. A guest physical address `PA` is therefore host
`window_base + offset + PA` without a second copy.

What the generated code does *not* have is a fixed relationship between a
guest *virtual* address and a host address. Every translated load or store
still:

1. strips a top byte when TBI is on,
2. walks a 512 KiB software TLB tagged by the guest page and access size,
3. falls back to the static MMU to apply the guest's own page tables,
4. only then adds a host delta and issues the native access.

Same-base unsigned runs already hoist (1)–(3) for a short burst of
`LDR`/`STR`. Attempts to generalise that hoist to `LDP`/`STP` and signed or
post-index forms hung `/init` or were a wash; a one-entry last-page delta
cache made the miss path more expensive than the hit it saved. The remaining
1.5–1.9× is exactly this per-access translation, plus the fact that compiled
code is full of pairs and negative unscaled offsets the current run
collector will not hoist.

The process-wide shared translation cache has a related, virtual-address
problem. An entry is keyed by guest PC plus the exact instruction words.
Publications are admitted only while two executors are live at once, and
unused entries can be reclaimed when those executors go away. A sequential
`gcc` → `cc1` → `as` pipeline, especially under ASLR, therefore compiles
`libc`, the dynamic linker, and the toolchain from scratch in each `exec`.
The isolated tiny-sha compile spent 1.40 s of 2.98 s in `JitCompiler`
(681k blocks, zero shared reuses).

## Goal

For guest user-mode addresses, make

```
host_va = guest_va + K
```

a constant `K` for the life of a task (and, if possible, the same `K` for
every task that maps a given file). Generated loads and stores then become
the guest's own instruction with a single `add` (or a RIP-relative
equivalent, but this host is arm64) and no TLB lookup, except on the first
touch of a page or when the guest mapping changes.

A stable guest user layout also makes a translation unique in the *file* it
came from, not the VA it happened to land at. The shared cache can then be
keyed by `(file identity, offset, instruction bytes, translation mode)` and
reused after `fork`/`exec` of `ash`, `gcc`, `cc1`, and `as`.

## Constraints

- The host is 16 KiB pages; the current guest is 4 KiB pages. `K` and every
  mapped span must be 16 KiB aligned so a 4 KiB guest page never shares a
  host page with a different protection or a different guest mapping.
- The Darwin native window, the MAP_JIT arena, the kernel image, thread
  stacks, and ordinary host allocations are already in the process. `guest_va
  + K` must never collide with them. The present window at
  `0x600000000000` is 5.4 GB and is reserved for *physical* RAM; a user VA
  space of 2^48 is far larger than that and cannot be placed inside it.
- Each guest task has its own page tables. Two tasks can map the same guest
  VA to different files, or leave it unmapped. A process-global `K` is only
  safe if the host mapping is per-task (or per-mm) and is switched when the
  executor changes address space.
- Guest `mmap`, `mprotect`, `munmap`, and CoW `fork` must update the host
  view. A stale writable alias is a correctness bug, not just a slow path.
- SME/TBI, misaligned accesses, and exclusives still have to be correct.
  Exclusives were what hung `/init` when writeback runs were lowered
  incorrectly; a fixed-offset fast path must not bypass the reservation
  logic.
- This is macOS. `vm_allocate` / `mmap` cannot arbitrarily occupy the
  entire user VA of the host process. The mapped set is only the pages the
  guest currently has mapped, placed at `guest_va + K`.

## Proposed layout

Pick one unused, 16 KiB-aligned host region whose base is `K`, with
`K % 16384 == 0`, large enough for the guest user range the ABI actually
uses (typically `[0, 2^39)` or the TASK_SIZE the kernel was built with, not
the whole 64-bit range). A concrete candidate on this Mac is a hole *below*
the Darwin native window or well above it, confirmed unoccupied at startup
with `mach_vm_region`, then reserved with `VM_FLAGS_ANYWHERE` disabled
(`mach_vm_map` at a fixed address, no access until a guest page is
installed).

Each guest mm_struct (or StaticGuestMemory generation) owns the host pages
in that region:

- On a guest user fault or `mmap`, map the underlying host RAM page (the
  same physical backing already in the native window) at `guest_va + K`
  with the guest's permissions, using a second mapping of the same
  VM object rather than a copy.
- On `mprotect` / `munmap` / CoW break, mirror the change at `guest_va + K`.
- On context switch to a different mm, either switch an address-space
  identifier (not available as a cheap user-space primitive on macOS) or
  keep one reserved region *per live mm* at the same `K` by mapping and
  unmapping, or — simpler and more robust — give each mm its own `K_mm`
  carved from a pool of reserved slots. The JIT records `K` in
  `JitChainState` at entry, so generated code is a single add from a
  register, not a process-wide constant baked into the cache.
- Kernel guest VAs (the high half) stay on the existing physical-window
  path. Only `EL0` user addresses use `K`.

`K` being per-mm, not per-process-global, avoids two tasks aliasing the
same host VA. If we later want one `K` for every task, the guest must run
with a fixed, non-overlapping user layout (ASLR off, a unique guest mm
id in the high bits, or a software "user-map generation" in those bits).
The first implementation should be per-mm.

## Generated-code fast path

In `emit_translate`, when the access is user and the current mm has a live
`K`:

```
host = guest_va + K          ; one add, K already in a callee-saved
                             ; register loaded at block entry
```

A cheap bounds check (`guest_va` is user, and optionally a bitmap of
installed pages) stays in front. Misses go to today's TLB + static MMU,
which installs the host alias and retries. Unaligned accesses that straddle
a 4 KiB guest page, device memory, and exclusives also take the existing
slow path.

Because `K` is in a register, a translation does not bake in a particular
mm and can still be shared by file+offset. The only thing a reused block
must not bake in is an absolute host address.

## Translation sharing, once VAs can move

Today's shared cache cannot survive `exec` even if we turned the
two-executor gate off. The host code stores guest PCs as literals
(`store_pc`, direct-link keys, ADRP constants). Two options, in order of
ambition:

1. **Fixed guest user base.** Disable ASLR in the UML guest
   (`kernel.randomize_va_space=0`) and pin the interpreter / ELF loader
   to a stable `ET_EXEC`-like base. Then PC+words is already a stable
   key, libc compiled during `apk` or during `gcc` can be reused by
   `cc1`, and the shared cache must *keep* unused entries instead of
   reclaiming them when the last executor for that mm drops. This is the
   smaller change and is the right first experiment. It does not by
   itself make loads/stores one add.
2. **File+offset key, relocatable output.** Key canonical translations
   by `(st_dev, st_ino, offset, mode, instruction bytes)`. At
   materialisation, slide every stored guest PC and direct-link key by
   `map_base - recorded_base`. Indirect sites compare the runtime target
   against a slid expected PC. This works with ASLR and is the right
   long-term key. It is also what a per-mm `K` needs, because the same
   libc page will not live at one VA forever.

Do not publish translations that bake host addresses, or a slide will
silently execute the wrong RAM.

## Why this is not "just add the physical-window offset"

`direct-root` already gives a constant physical offset. The JIT would still
need the guest PTE to turn a VA into a PA on every access. The whole point
of a user `K` is to pre-apply that PTE at `mmap` time, once per page, and
then stay on the guest's own addressing until the mapping changes.

## Suggested implementation order

1. Inventory host VM holes at uml-darwin startup and reserve a per-mm user
   region whose alignment matches the 16 KiB host page. Document the
   chosen `K` in the boot log the same way the native window is logged
   today.
2. Mirror guest user `mmap` / `mprotect` / `munmap` / CoW into that
   region, with a test that two mm's do not alias and that a 4 KiB
   protection change does not leave a neighbouring 4 KiB writable on the
   16 KiB host page.
3. Add the `guest_va + K` fast path behind a flag, with exclusives and
   straddles still on the old translator. Re-measure openssl evp and
   tiny-sha; keep the change only if the 1.5–1.9× drops without
   regressing the shell or compile.
4. Stop reclaiming unused shared translations, allow publication from a
   single live executor, and measure `gcc` with guest ASLR off. If
   compile time of new blocks drops from ~1.4 s toward zero on a second
   `cc1`, land that even before file+offset keys.
5. Only then key the shared cache by file+offset and slide PCs, which is
   what makes the same translations work with ASLR and with a per-mm `K`.

## Non-goals

- Mapping the guest kernel high half at a fixed user-style `K`. Kernel
  addresses already have the physical window.
- A process-global identity map of the entire 48-bit guest VA onto the
  host. There is no such hole, and two guests would smash each other.
- Changing macOS, the Keychain, brew, or the iPhone to make more VA
  available.
