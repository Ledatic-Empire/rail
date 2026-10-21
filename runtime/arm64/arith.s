// rt_arith: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ let rsub
_rail_sub:
    tst x1, #1
    b.eq .Lsub_fl
    tst x0, #1
    b.eq .Lsub_fl
    asr x1, x1, #1
    asr x0, x0, #1
    sub x0, x1, x0
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lsub_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fsub d0, d1, d0
    mov x0, #16
    bl _rail_alloc
    mov x1, #6
    str x1, [x0]
    str d0, [x0, #8]
    ldp x29, x30, [sp], #16
    ret

//@ let rmul
_rail_mul:
    tst x1, #1
    b.eq .Lmul_fl
    tst x0, #1
    b.eq .Lmul_fl
    asr x1, x1, #1
    asr x0, x0, #1
    mul x0, x1, x0
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lmul_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fmul d0, d1, d0
    mov x0, #16
    bl _rail_alloc
    mov x1, #6
    str x1, [x0]
    str d0, [x0, #8]
    ldp x29, x30, [sp], #16
    ret

//@ let rdiv
_rail_div:
    tst x1, #1
    b.eq .Ldiv_fl
    tst x0, #1
    b.eq .Ldiv_fl
    asr x1, x1, #1
    asr x0, x0, #1
    sdiv x0, x1, x0
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Ldiv_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fdiv d0, d1, d0
    mov x0, #16
    bl _rail_alloc
    mov x1, #6
    str x1, [x0]
    str d0, [x0, #8]
    ldp x29, x30, [sp], #16
    ret

//@ let rmod
_rail_mod:
    tst x1, #1
    b.eq .Lmod_fl
    tst x0, #1
    b.eq .Lmod_fl
    asr x1, x1, #1
    asr x0, x0, #1
    sdiv x2, x1, x0
    msub x0, x2, x0, x1
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lmod_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fmov x2, d1
    fmov x3, d0
    fmov d0, x2
    fmov d1, x3
    bl _fmod
    mov x0, #16
    bl _rail_alloc
    mov x1, #6
    str x1, [x0]
    str d0, [x0, #8]
    ldp x29, x30, [sp], #16
    ret

// Ordered comparisons dispatch like _rail_eq: two heap operands are boxed
// floats (tag 6) or strings (byte-wise via _strcmp, x1 is the LEFT operand).
// Until 2026-09-11 there was no string branch: `"abc" < "abd"` compared
// whatever eight bytes sat at offset 8 of each string, so the answer
// depended on allocation order (findings F-5000-3, t207). Two non-int
// operands that are not both strings go through _rail_fval (boxed, raw or
// int, each side independently). tools/x86_rt.s still lacks both.
//@ let rlt
_rail_lt:
    tst x1, #1
    b.eq .Llt_heap
    tst x0, #1
    b.eq .Llt_fl
    cmp x1, x0
    cset x0, lt
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Llt_heap:
    tst x0, #1
    b.ne .Llt_fl
    cbz x1, .Llt_raw
    cbz x0, .Llt_raw
    lsr x2, x1, #47
    cbnz x2, .Llt_fl
    cmp x1, #4095
    b.ls .Llt_fl
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.eq .Llt_fl
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, x1
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    mov x1, x0
    ldr x0, [x29, #24]
    bl _strcmp
    cmp x0, #0
    cset x0, lt
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Llt_raw:
    cmp x1, x0
    cset x0, lt
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Llt_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fcmp d1, d0
    cset x0, lo
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

//@ let rgt
_rail_gt:
    tst x1, #1
    b.eq .Lgt_heap
    tst x0, #1
    b.eq .Lgt_fl
    cmp x1, x0
    cset x0, gt
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lgt_heap:
    tst x0, #1
    b.ne .Lgt_fl
    cbz x1, .Lgt_raw
    cbz x0, .Lgt_raw
    lsr x2, x1, #47
    cbnz x2, .Lgt_fl
    cmp x1, #4095
    b.ls .Lgt_fl
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.eq .Lgt_fl
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, x1
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    mov x1, x0
    ldr x0, [x29, #24]
    bl _strcmp
    cmp x0, #0
    cset x0, gt
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lgt_raw:
    cmp x1, x0
    cset x0, gt
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lgt_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fcmp d1, d0
    cset x0, gt
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

//@ let rle
_rail_le:
    tst x1, #1
    b.eq .Lle_heap
    tst x0, #1
    b.eq .Lle_fl
    cmp x1, x0
    cset x0, le
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lle_heap:
    tst x0, #1
    b.ne .Lle_fl
    cbz x1, .Lle_raw
    cbz x0, .Lle_raw
    lsr x2, x1, #47
    cbnz x2, .Lle_fl
    cmp x1, #4095
    b.ls .Lle_fl
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.eq .Lle_fl
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, x1
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    mov x1, x0
    ldr x0, [x29, #24]
    bl _strcmp
    cmp x0, #0
    cset x0, le
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lle_raw:
    cmp x1, x0
    cset x0, le
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lle_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fcmp d1, d0
    cset x0, ls
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

//@ let rge
_rail_ge:
    tst x1, #1
    b.eq .Lge_heap
    tst x0, #1
    b.eq .Lge_fl
    cmp x1, x0
    cset x0, ge
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lge_heap:
    tst x0, #1
    b.ne .Lge_fl
    cbz x1, .Lge_raw
    cbz x0, .Lge_raw
    lsr x2, x1, #47
    cbnz x2, .Lge_fl
    cmp x1, #4095
    b.ls .Lge_fl
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.eq .Lge_fl
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, x1
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    mov x1, x0
    ldr x0, [x29, #24]
    bl _strcmp
    cmp x0, #0
    cset x0, ge
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lge_raw:
    cmp x1, x0
    cset x0, ge
    lsl x0, x0, #1
    orr x0, x0, #1
    ret
.Lge_fl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_fval1
    bl _rail_fval
    fcmp d1, d0
    cset x0, ge
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret

// rc_alloc: allocate refcounted object. x0 = size (tagged). Returns ptr to data (refcount at ptr-8)
//@ let rrcalloc
_rail_rc_alloc:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    asr x0, x0, #1
    add x0, x0, #8
    bl _malloc
    mov x1, #1
    str x1, [x0]
    add x0, x0, #8
    ldp x29, x30, [sp], #16
    ret

// rc_release: decrement refcount, free if zero
//@ let rrcrelease
_rail_rc_release:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x1, [x0, #-8]
    sub x1, x1, #1
    str x1, [x0, #-8]
    cbnz x1, .Lrc_keep
    sub x0, x0, #8
    bl _free
.Lrc_keep:
    ldp x29, x30, [sp], #16
    ret

//@ cat rsub, rmul, rdiv, rmod, rlt, rgt, rle, rge, rrcalloc, rrcrelease
