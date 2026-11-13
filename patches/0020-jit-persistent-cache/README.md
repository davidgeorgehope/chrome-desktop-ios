# Persistent shared-translation cache

The in-memory shared cache is already keyed by file+offset, but that file
identity is a process-lifetime code-page stamp. It cannot survive `exec`
of a new process after reboot, so a warm Firefox still cold-translates
libxul.

This store writes admitted translations to disk, keyed by the *content
hash of the guest code page* plus the page offset and codegen profile.
On the next launch, a miss in RAM looks up that durable key, checks the
stored guest instruction bytes against the bytes just fetched (and the
optional source-image fingerprint), and materializes the translation with
the same PC slide the RAM cache already uses. A hash, mtime, size, UUID,
or CRC mismatch is a miss: the compiler runs as before. Nothing on the
disk path can install host pointers; records keep the same relocatable
template as a live publication. Reloc cells are zeroed before a record is
written, and any leftover 64-bit value in the macOS user range
[0x100000000, 0x200000000) is refused on remember and on lookup (safe
miss / skip). A first cache that still carried a cold-process host
pointer panicked a warm boot; wipe that generation.

Source fingerprint: set `UML_JIT_PERSISTENT_CACHE_SOURCE` (or
`KERNARIUM_JIT_PERSISTENT_CACHE_SOURCE`) to the rootfs image. The store
records size, mtime, and the ext4 UUID when present. A different image
retires the old files (`data.jtc.stale`) and starts empty. Prefer the
stable read-only image, not a per-boot `.rw.ext4` copy whose mtime jumps.

Environment:

```
UML_JIT_PERSISTENT_CACHE=/Volumes/KernariumCS/jit-cache/uml-darwin
UML_JIT_PERSISTENT_CACHE_SOURCE=/path/to/alpine-...-labwc.ext4
UML_JIT_SHARED_STATS=1
```

`KERNARIUM_JIT_*` is accepted as an alias. The cache is **off by default**:
it stays off when the directory env is unset or empty, and find/publish
then skip the page-hash hook so the default path does not pay persist I/O
or hashing. Leave it off until a warm start clearly beats the persist-off baseline. Persist-on Designed-for-iPad hung in `openssl speed -evp aes-256-cbc` on the 8192-byte column (persist-off completed that column). On Designed-for-iPad, pass the same variables
through `TEST_RUNNER_` and put the directory in the app container
`Documents` (the sandbox cannot write `/Volumes/KernariumCS`). Atexit (and every 4096 new records) flushes an
index beside the append-only `data.jtc`. Corrupt records are skipped.

The official 4K uml-darwin identity is not bumped; rebuild the
macos-integration side binary (and the ios-device runtime for My Mac).
Put the uml-darwin cache on KernariumCS (several GiB for one Firefox
unique set). Do not use a 4 GiB process budget on the 16 GiB mini.

Apply: `python3 patches/0020-jit-persistent-cache/apply.py` from the
Kernarium tree after 0019.
