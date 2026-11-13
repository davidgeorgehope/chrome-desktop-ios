# Simulator `vm_region_64` for `inventory_holes()`

The iPhoneSimulator 26.5 SDK rejects `<mach/mach_vm.h>` with
`#error mach_vm.h unsupported`. `darwin/memory/mmu/user_map.cpp` used
`mach_vm_region` from that header in `inventory_holes()`, so
`cmake --build --preset kernarium-ios-simulator` failed after the 0013
JIT sources were applied.

This change switches that walk to `vm_region_64` and `<mach/vm_map.h>`,
which the Simulator SDK provides. Behavior is the same hole inventory;
only the Mach API changes.

Apply on a Kernarium checkout with:

```sh
cp patches/0014-simulator-vm-region-64/user_map.cpp \
  /path/to/Kernarium/darwin/memory/mmu/user_map.cpp
```

or `patch -p1` from the Kernarium root with `inventory_holes.patch`.
`scripts/build-kernarium-simulator.sh` does the copy for you, together
with the 0013 JIT sources.

Do not rebuild the official macOS `uml-darwin` identity from this tree
after applying these sources. The macOS Metal present path is unchanged
by this patch.
