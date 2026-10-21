// rt_gc_2: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// _gc_try_mark: x0=value. Check if heap ptr, mark if valid object, push children.
//@ piece
_gc_try_mark:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
// Check: not tagged int (bit 0), in heap range [_rail_heap..heap_ptr), 8-byte aligned
//@ piece
    tst x0, #1
    b.ne .Ltm_ret
//@ piece
    adrp x1, _rail_heap_base@PAGE
    ldr x1, [x1, _rail_heap_base@PAGEOFF]
    cmp x0, x1
    b.lo .Ltm_ret
//@ piece
    adrp x1, _rail_heap_ptr@PAGE
    ldr x1, [x1, _rail_heap_ptr@PAGEOFF]
    cmp x0, x1
    b.hs .Ltm_ret
//@ piece
    tst x0, #7
    b.ne .Ltm_ret
// Load tag, mask mark bit, check valid range 1-9
//@ piece
    ldr x1, [x0]
    and x2, x1, #0x7fffffffffffffff
    cmp x2, #1
    b.lo .Ltm_ret
    cmp x2, #9
    b.hi .Ltm_ret
// Check not already marked (bit 63)
//@ piece
    tbnz x1, #63, .Ltm_ret
// Set mark bit
//@ piece
    orr x1, x1, #0x8000000000000000
    str x1, [x0]
// Push to mark stack
//@ piece
    str x0, [x29, #16]
//@ piece
    adrp x1, _gc_mark_top@PAGE
    add x1, x1, _gc_mark_top@PAGEOFF
    ldr x3, [x1]
//@ piece
    adrp x4, _gc_mark_cap@PAGE
    ldr x4, [x4, _gc_mark_cap@PAGEOFF]
    cmp x3, x4
    b.lo .Ltm_push
// The stack is full: double it and copy the pending entries over. Until 2026-10-19 the push
// was skipped instead: the object stayed marked, its children were never scanned, and the
// sweep freed them live (a list of 600,000 two-element lists lost its spine at cell 524,292).
// The old block is not returned (_free is a no-op on macOS); growth is geometric, so at most
// one extra copy of the final size is ever held. No memory at all is fatal, said out loud.
//@ piece
    str x3, [x29, #24]
    lsl x0, x4, #4
    bl _malloc
    cbz x0, .Ltm_oom
    str x0, [x29, #40]
//@ piece
    adrp x1, _gc_mark_stack@PAGE
    ldr x1, [x1, _gc_mark_stack@PAGEOFF]
    adrp x2, _gc_mark_cap@PAGE
    ldr x2, [x2, _gc_mark_cap@PAGEOFF]
    lsl x2, x2, #3
    bl _memcpy
//@ piece
    ldr x0, [x29, #40]
    adrp x1, _gc_mark_stack@PAGE
    str x0, [x1, _gc_mark_stack@PAGEOFF]
//@ piece
    adrp x1, _gc_mark_cap@PAGE
    ldr x2, [x1, _gc_mark_cap@PAGEOFF]
    lsl x2, x2, #1
    str x2, [x1, _gc_mark_cap@PAGEOFF]
//@ piece
    ldr x3, [x29, #24]
    adrp x1, _gc_mark_top@PAGE
    add x1, x1, _gc_mark_top@PAGEOFF
//@ piece
.Ltm_push:
    adrp x5, _gc_mark_stack@PAGE
    ldr x5, [x5, _gc_mark_stack@PAGEOFF]
//@ piece
    ldr x0, [x29, #16]
    str x0, [x5, x3, lsl #3]
    add x3, x3, #1
    str x3, [x1]
//@ piece
.Ltm_ret:
    ldp x29, x30, [sp], #48
    ret
//@ piece
.Ltm_oom:
    mov x0, #2
    adrp x1, _gc_mark_msg@PAGE
    add x1, x1, _gc_mark_msg@PAGEOFF
    mov x2, #30
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #1
    bl _exit

