# Fixed-offset guest user memory mapping

This is a design. A first env-gated prototype was tried on macOS uml-darwin
on 13 Nov 2026 and is **not landed** (see "Prototype status" below). It is
the memory-side follow-on to the 12 Nov 2026 JIT CPU profile
(`scripts/cpu-benches/RESULTS.md`).
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
5. Key the shared cache by file+offset and slide PCs, which is what
   makes the same translations work with ASLR and with a per-mm `K`.
   Landed in `patches/0009-jit-file-offset-aslr`: the file identity is
   the host code-page stamp of the physical backing page, plus the
   guest page offset. Baked guest PCs and link keys slide by
   `new_pc - recorded_pc`.

## Non-goals

- Mapping the guest kernel high half at a fixed user-style `K`. Kernel
  addresses already have the physical window.
- A process-global identity map of the entire 48-bit guest VA onto the
  host. There is no such hole, and two guests would smash each other.
- Changing macOS, the Keychain, brew, or the iPhone to make more VA
  available.

## Shared-translation budget (landed 12 Nov 2026)

`patches/0007-jit-shared-translations`. The process-wide shared cache is charged against the leftover of the whole-process JIT budget after every vCPU's private L1 (capped at 256 MiB). The previous default of `guest_memory/2` left almost no leftover at `mem=2G` `ncpus=8`, so publication rejected ~1.7M admits. The default total is now `guest/2 + 256 MiB * ncpus + 1 GiB` (4 GiB at the usual 2 GiB/8 vCPU launch): private L1s fill to the 256 MiB cap and the shared cache gets a 2 GiB leftover. Out-of-range relocatable link pointers use a nearby literal island rather than a host-baked MOV-wide stub, publication is allowed with one live executor, and a translation may carry relocatable slots. The cap was first raised from 2 to `maximum_block_instructions` (64), then, in `patches/0010-jit-reloc-cap`, to `maximum_block_instructions * 2 + 4` (132) because guest-PC literals from 0009 made a 64-instruction block overflow 64 slots and rejected 8,909 unique gcc publications. Entries were keyed by guest PC + instruction words until `patches/0009-jit-file-offset-aslr`, which also indexes by the host code-page stamp plus page offset and slides baked guest PCs (`store_pc`, ADR/ADRP, BL return, link keys) so a warm `cc1` hits under ASLR. A later Firefox-content-process miss was not a keying failure: at the default 3 GiB leftover the cache filled, unused reclaim could not evict L1-pinned entries, and ASLR'd PCs hashed to other shards, so new publications were rejected. `patches/0011-jit-shared-evict-on-full` evicts in-use entries and reclaims across shards when the budget is exhausted (already-materialized L1 copies stay valid). A larger `--jit-cache-budget=8G` holds one Firefox unique set without evicting. The official 4K default budget and identity are unchanged.


## Prototype status (13 Nov 2026) — not landed

An env-gated prototype (`UML_JIT_USER_MAP=1`) was built on macOS uml-darwin.
It reserved per-mm slots, mirrored uniform 16 KiB guest spans with `vm_remap`
of the existing native-window backing, bound `K` and an installed-page bitmap
into `JitChainState`, and used a flag-free `guest_va + K` fast path in
`emit_translate` (exclusives, atomics, and 4 KiB-straddling accesses stayed
on the software TLB). Faults in the reserved region retried after a
map-and-install in the SIGSEGV/SIGBUS handler.

It booted, ran apk, dash, and a gcc compile (cold and warm exit 0). It
**regressed** the walls we care about, so it was not committed:

- `sh_loop_dash` 0.18 s → 0.29–0.30 s
- compile cold 2.07 s → 2.44–2.48 s
- compile warm 1.16 s → 1.46 s

The extra bounds+bitmap checks on every load/store, with the TLB path still
taken when a 16 KiB span is not uniformly remappable, are the likely tax.
A process-wide mutex on every `run_block` bind was removed (lock-free
publish of `K` and the bitmap pointer); the regression remained.

### Blockers

- **UML native window layout.** The process already reserves the physical
  RAM window at `0x600000000000-0x60014000c000` (5.4 GiB, 16 KiB host pages,
  `direct-root=yes`). `mach_vm_region` at startup showed a ~96 TiB hole
  below it (`0x7000000000-0x600000000000`) and a ~32 TiB hole above it
  (`0x60014000c000-0x800000000000`, the 47-bit guest limit). Those holes
  are not all mmapable: `MAP_NORESERVE` of 8 TiB at `0x780000000000` and of
  1 TiB at `0x7f0000000000` both failed with `ENOMEM`. A compact pack of 32
  slots × 32 GiB at `0x600800000000` did reserve. A contiguous TASK_SIZE
  (2^39–2^48) alias does not fit beside the native window, the MAP_JIT
  arena, and ordinary host allocations, and Darwin will not hand over the
  whole inventoried hole.
- **47-bit host vs high musl PIE.** Guest user VAs under ASLR sit near
  `0x7fff...`, just below `DARWIN_UML_GUEST_ADDRESS_LIMIT` (2^47). The
  working reservation used a process-wide guest window of the top 32 GiB
  (`0x7ff800000000-0x800000000000`) and a per-mm `K` (slot 0's `K` was
  `0xffffe01000000000`, a wrap, not identity). Heap or mmap below that
  window stays on the software TLB. Identity (`K=0`) at the PIE addresses
  themselves was not mmapable at the sizes we tried.
- **16 KiB host pages vs 4 KiB guest pages.** A host mapping is 16 KiB, so
  only a 16 KiB-aligned guest span whose four 4 KiB pages share one
  protection and are physically contiguous in the native window can be
  remapped as `guest_va + K`. Mixed or sparse 16 KiB spans stay on the TLB;
  a blanket `add K` without a bitmap would SIGSEGV or incorrectly expose
  an unmapped 4 KiB neighbour. That bitmap+fallback is what the prototype
  emitted, and it cost more than it saved on dash and gcc.
- **Per-mm slots, not a process-global identity map.** Two tasks can map
  the same guest VA differently. The prototype carved 32 slots from the
  reserved pack, one per live mm, with `K` in `JitChainState` so
  translations stay shareable. 32 concurrent mm's is a practical cap, not
  a TASK_SIZE solution.
- **No cheap way to complete a guest fault from SIGSEGV** when the fast
  path has already rewritten the address to `guest + K` and the page is
  legitimately unmapped or mixed. The bitmap is what keeps those accesses
  on the TLB path so the existing fault label can fire.

A later attempt should either map only proven-uniform 16 KiB spans *and*
avoid a per-access bitmap (for example a same-page run that already hoists
translation), or find a way to install every 4 KiB user page without
breaking 16 KiB host isolation. It must beat 0.18 s dash and 1.16 s warm
compile with the flag off, not just boot.

## 16 KiB guest PAGE_SIZE (13 Nov 2026) — experimental, not landed

A 16 KiB guest `PAGE_SIZE` for arm64 Darwin UML is **feasible** and was
booted, but it is not an accepted product and it is not in
`linux-ios-fast` yet. It is the layout the fixed-offset user map wants:
one guest page is one Darwin host page, so the 4-into-1 mixed-span
bitmap that taxed the 4 KiB prototype is no longer required for ordinary
pages.

### What was verified

- Guest `getconf PAGE_SIZE=16384`. A 1 GiB launch reported `Total pages:
  65536` (1 GiB / 16 KiB).
- The kernel is an experimental out-of-tree build from a detached worktree
  of the accepted source (`/Volumes/KernariumCS/linux-16k`, commit
  `8246678b2`), not a dirtying of the accepted tree or a change of
  `accepted-4k.env`. Config: `CONFIG_PAGE_SIZE_16KB=y`,
  `CONFIG_PAGE_SHIFT=14`, `CONFIG_KERNEL_STACK_ORDER=2` (64 KiB stacks,
  same as order-4 × 4 KiB). Four-level UML page tables still give a
  47-bit VA (`PGDIR_SHIFT = 14 + 3×11`), which matches
  `DARWIN_UML_GUEST_ADDRESS_LIMIT`.
- Darwin `tlb.c` host-page packing was generalized from a hard `4 × 4 KiB`
  to `DARWIN_HOST_PAGE_SIZE / PAGE_SIZE` (4 or 1). The official 4 KiB path
  is unchanged when `PAGE_SIZE` is 4096.
- A host build option `UML_GUEST_16K_PAGES` (preset
  `macos-integration-16k`, arm64 only) sets
  `DARWIN_UML_GUEST_PAGE_SIZE=16384`. The canonical ABI header and
  `identity.env` (version 26, fingerprint `0x1d7ce579d497fc37`) were
  **left unchanged**; a generated header is `-include`d only for C/C++/ObjC++
  so the 4 KiB-only `static_assert` does not fire. `tlb.hpp` and the
  gadget `PAGE_SHIFT` follow the compile definition.
- The official artifact importer still requires a 4 KiB bundle
  (`kernel_artifact.py` has `GUEST_PAGE_SIZE = 4096`). A 16K uml-darwin
  therefore imports the accepted 4 KiB artifact for CMake identity, then
  retargets the embedded `__TEXT,__uml_elf` at
  `-DUML_16K_KERNEL_IMAGE=` (a strip-debug copy of the experimental
  vmlinux). Mixing a 16K host with a 4K kernel, or the reverse, is
  unsupported.
- Alpine 3.24.2 minimal booted, mounted ext4, ran `/bin/busybox` ash, and
  powered off with `result=0`.
- The official ASLR-on CPU suite was then measured on the same overnight
  mini (2 GiB, 8 cpus, profiler off, packages installed each boot from
  `notes/cpu-benches/apks.tar`) on three setups: the official 4 KiB
  binary, the experimental 16K binary with `UML_JIT_USER_MAP` off, and
  16K with `UML_JIT_USER_MAP=1`. Walls, 13 Nov 2026, America/New_York:

  | bench | 4K baseline | 16K flag-off | 16K + user-map |
  | --- | ---: | ---: | ---: |
  | dash | 0.18 s | 0.18 s | 0.28 s |
  | ash | 0.18 s | 0.17 s | 0.28 s |
  | apk add (offline) | 2.80 s | 2.68 s | 3.29 s |
  | evp aes-256-cbc 16 KiB | 1,039,985.32k | 1,044,921.11k | 1,040,143.70k |
  | evp sha256 16 KiB | 1,790,006.61k | 1,806,035.63k | 1,734,907.22k |
  | compile tiny-sha (cold) | 2.11 s | 1.90 s | 2.24 s |
  | compile tiny-sha (warm) | 1.15 s | 1.12 s | 1.33 s |
  | tiny-sha run | 1.171529 s / 81.94 MiB/s | 1.175699 s / 81.65 MiB/s | 1.211553 s / 79.24 MiB/s |
  | tight loop | 0.49 s | 0.48 s | 0.76 s |

  Logs: `notes/jit-baseline/16k/official-4k-20261113-013849.log`,
  `official-16k-20261113-013641.log`,
  `official-16k-usermap-20261113-013750.log`.
- 16K flag-off is even with 4K on dash and the tight loop, and a little
  ahead on the compiles and evp rates — within ordinary run noise for
  most rows, not a product change. `UML_JIT_USER_MAP=1` on 16K **lost**:
  dash 1.56× slower than 16K flag-off, warm compile 1.19×, tight loop
  1.58×, evp sha256 ~4 % slower. The reservation still succeeded as the
  compact pack (32 × 32 GiB at `0x600800000000`, guest window the top
  32 GiB, slot0 `K=0xffffe01000000000`; a first 1 TiB reserve still
  fails with `errno=12`). The prototype is therefore still not landed,
  even as an opt-in experimental preset. A 16K guest page is one Darwin
  host page, so the 4-into-1 mixed-span bitmap is no longer the excuse;
  the remaining tax is in the user-map load/store sequences, binding, or
  fault path, and has to be fixed before the flag can be a default or a
  documented preset.

### What still blocks an official 16K product

- `kernel_artifact.py` rejects any manifest whose `page_size` is not
  4096; `publish_artifact` also hardcodes `4k` in the directory name.
  `build-kernel.sh` prints "built … 4k Darwin UML kernel" and requires a
  clean source tree whose hash matches `UML_KERNEL_FINAL_TREE`. A real
  16K accepted artifact would need a page-size-aware verifier, a new
  `accepted-16k.env`, a documented `build-kernel.sh --pages 16k` (or
  equivalent) path, and a new tree hash if the tlb.c / Kconfig /
  Makefile-os-Darwin patches are replayed into the official series.
- `darwin-uml.fragment` pins `CONFIG_PAGE_SIZE_4KB=y` and
  `CONFIG_KERNEL_STACK_ORDER=4`. The 16K overlay must keep being applied
  last (and must keep stacks at 64 KiB via order 2).
- `arch/um/Kconfig` advertised only `HAVE_PAGE_SIZE_4KB`. The
  experimental worktree also selects `HAVE_PAGE_SIZE_16KB`. That select
  is not in the official series.
- x86_64 guests stay on 4 KiB. The CMake option is fatal on that slice.
- Official CPU benches have now been measured (table above). 16K
  flag-off does not clearly beat 4K, and 16K + user-map regresses, so
  neither the 16K preset nor the user-map flag is landed. The official
  4 KiB identity (`identity.env` v26, `0x1d7ce579d497fc37`) is unchanged.

The user-map prototype stays behind `UML_JIT_USER_MAP` in the Kernarium
tree on the mini. It must beat 0.18 s dash and 1.15 s warm compile with
the flag off (and must not regress the tight loop past 0.49 s) before it
is committed as an opt-in experimental preset.
