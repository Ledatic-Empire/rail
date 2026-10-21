// rt_gc_3: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// _gc_drain: process mark stack, call try_mark on children
//@ piece
_gc_drain:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
//@ piece
.Ldrain_loop:
//@ piece
    adrp x0, _gc_mark_top@PAGE
    add x0, x0, _gc_mark_top@PAGEOFF
    ldr x1, [x0]
    cbz x1, .Ldrain_done
//@ piece
    sub x1, x1, #1
    str x1, [x0]
//@ piece
    adrp x2, _gc_mark_stack@PAGE
    ldr x2, [x2, _gc_mark_stack@PAGEOFF]
    ldr x3, [x2, x1, lsl #3]
// x3 = object ptr. Load tag.
//@ piece
    str x3, [x29, #16]
    ldr x4, [x3]
    and x4, x4, #0x7fffffffffffffff
// Case 1: Cons, mark head and tail
//@ piece
    cmp x4, #1
    b.ne .Ldrain_c3
    ldr x0, [x3, #8]
    bl _gc_try_mark
    ldr x3, [x29, #16]
    ldr x0, [x3, #16]
    bl _gc_try_mark
    b .Ldrain_loop
// Case 3: Tuple, mark all elements
//@ piece
.Ldrain_c3:
    cmp x4, #3
    b.ne .Ldrain_c4
//@ piece
    ldr x5, [x3, #-8]
    sub x5, x5, #8
    lsr x5, x5, #3
    mov x6, #0
    str x5, [x29, #24]
//@ piece
.Ldrain_t_loop:
    ldr x5, [x29, #24]
    cmp x6, x5
    b.hs .Ldrain_loop
    str x6, [x29, #32]
    ldr x3, [x29, #16]
    add x7, x6, #1
    ldr x0, [x3, x7, lsl #3]
    bl _gc_try_mark
    ldr x6, [x29, #32]
    add x6, x6, #1
    b .Ldrain_t_loop
// Case 4: Closure, mark captures
//@ piece
.Ldrain_c4:
    cmp x4, #4
    b.ne .Ldrain_c5
//@ piece
    ldr x5, [x3, #16]
    mov x6, #0
    str x5, [x29, #24]
//@ piece
.Ldrain_cl_loop:
    ldr x5, [x29, #24]
    cmp x6, x5
    b.hs .Ldrain_loop
    str x6, [x29, #32]
    ldr x3, [x29, #16]
    add x7, x6, #3
    ldr x0, [x3, x7, lsl #3]
    bl _gc_try_mark
    ldr x6, [x29, #32]
    add x6, x6, #1
    b .Ldrain_cl_loop
// Case 5: ADT, mark fields
//@ piece
.Ldrain_c5:
    cmp x4, #5
    b.ne .Ldrain_c7
//@ piece
    ldr x5, [x3, #-8]
    sub x5, x5, #16
    lsr x5, x5, #3
    mov x6, #0
    str x5, [x29, #24]
//@ piece
.Ldrain_a_loop:
    ldr x5, [x29, #24]
    cmp x6, x5
    b.hs .Ldrain_loop
    str x6, [x29, #32]
    ldr x3, [x29, #16]
    add x7, x6, #2
    ldr x0, [x3, x7, lsl #3]
    bl _gc_try_mark
    ldr x6, [x29, #32]
    add x6, x6, #1
    b .Ldrain_a_loop
// Case 7: Array, mark all elements
//@ piece
.Ldrain_c7:
    cmp x4, #7
    b.ne .Ldrain_c8
//@ piece
    ldr x5, [x3, #8]
    mov x6, #0
    str x5, [x29, #24]
//@ piece
.Ldrain_ar_loop:
    ldr x5, [x29, #24]
    cmp x6, x5
    b.hs .Ldrain_loop
    str x6, [x29, #32]
    ldr x3, [x29, #16]
    add x7, x6, #2
    ldr x0, [x3, x7, lsl #3]
    bl _gc_try_mark
    ldr x6, [x29, #32]
    add x6, x6, #1
    b .Ldrain_ar_loop
// Case 8: Error, mark message string
//@ piece
.Ldrain_c8:
    cmp x4, #8
    b.ne .Ldrain_loop
    ldr x0, [x3, #8]
    bl _gc_try_mark
    b .Ldrain_loop
//@ piece
.Ldrain_done:
    ldp x29, x30, [sp], #64
    ret

