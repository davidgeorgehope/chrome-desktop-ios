.text
/* StikJIT universal protocol (INTEGRATION.md). Public wire format:
 *   JIT26PrepareRegion(addr, len): mov x16, #1; brk #0xf00d; ret
 *   JIT26Detach():                 mov x16, #0; brk #0xf00d; ret
 * Arguments in x0/x1; prepare returns the RX address in x0.
 * A brk with no script attached is a fatal SIGTRAP; the C trap
 * handler must be installed first.
 */
#if defined(__aarch64__) || defined(__arm64__)

.align 2
.globl _DeskBrowserJit26PrepareRegion
_DeskBrowserJit26PrepareRegion:
    mov     x16, #1
    brk     #0xf00d
    ret

.align 2
.globl _DeskBrowserJit26Detach
_DeskBrowserJit26Detach:
    mov     x16, #0
    brk     #0xf00d
    ret

#endif /* aarch64 */
