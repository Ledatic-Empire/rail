// rt_array: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ piece
_rail_arr_new:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    asr x2, x0, #1
    cmp x2, #0
    b.lt .Larn_neg
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

// A negative length and an index outside 0..len-1 end the program with a message and exit
// code 1 (2026-11-18). Before, arr_new of a negative length and arr_get past the end read or
// wrote whatever was there. arr_get and arr_set are inline in the compiler and call
// _rail_arr_oob; the float array routines (float.s) branch here too.
.Larn_neg:
_rail_arr_neg:
    adrp x1, _rail_arr_neg_msg@PAGE
    add x1, x1, _rail_arr_neg_msg@PAGEOFF
    mov x2, #31
    b .Larr_die
_rail_arr_oob:
    adrp x1, _rail_arr_oob_msg@PAGE
    add x1, x1, _rail_arr_oob_msg@PAGEOFF
    mov x2, #32
.Larr_die:
    mov x0, #2
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #1
    bl _exit
.data
_rail_arr_oob_msg:
    .asciz "rail: array index out of bounds\n"
_rail_arr_neg_msg:
    .asciz "rail: arr_new: negative length\n"
.p2align 3
.text

