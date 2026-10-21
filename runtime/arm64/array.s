// rt_array: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ piece
_rail_arr_new:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    asr x2, x0, #1
    str x2, [x29, #16]
    str x1, [x29, #24]
    lsl x0, x2, #3
    add x0, x0, #16
    bl _rail_alloc
    str x0, [x29, #32]
    mov x3, #7
    str x3, [x0]
    ldr x2, [x29, #16]
    str x2, [x0, #8]
    ldr x1, [x29, #24]
    mov x3, #0
.Larn_loop:
    cmp x3, x2
    b.hs .Larn_done
    add x4, x3, #2
    ldr x5, [x29, #32]
    str x1, [x5, x4, lsl #3]
    add x3, x3, #1
    b .Larn_loop
.Larn_done:
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #48
    ret

