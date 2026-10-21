// rt_float: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// show_float: d0 = double, returns string pointer in x0
//@ let rshowfx
_rail_show_float_exact:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str d0, [x29, #16]
    mov x0, #40
    bl _malloc
    str x0, [x29, #24]
    ldr d0, [x29, #16]
    str d0, [sp, #-16]!
    ldr x0, [x29, #24]
    mov x1, #40
    adrp x2, _fmt_g17@PAGE
    add x2, x2, _fmt_g17@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #24]
    bl _rail_wrap_str
    str x0, [x29, #16]
    ldr x0, [x29, #24]
    bl _free
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

//@ let rshowf
_rail_show_float:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str d0, [x29, #16]
    mov x0, #32
    bl _malloc
    str x0, [x29, #24]
    ldr d0, [x29, #16]
    str d0, [sp, #-16]!
    ldr x0, [x29, #24]
    mov x1, #32
    adrp x2, _fmt_gbare@PAGE
    add x2, x2, _fmt_gbare@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #24]
    bl _rail_wrap_str
    str x0, [x29, #16]
    ldr x0, [x29, #24]
    bl _free
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

// print_float: d0 = double, prints with newline
//@ let rprintf
_rail_print_float:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str d0, [x29, #16]
    mov x0, #32
    bl _malloc
    str x0, [x29, #24]
    ldr d0, [x29, #16]
    str d0, [sp, #-16]!
    ldr x0, [x29, #24]
    mov x1, #32
    adrp x2, _fmt_gbare@PAGE
    add x2, x2, _fmt_gbare@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #24]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #24]
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov w0, #10
    strb w0, [x29, #32]
    mov x0, #1
    add x1, x29, #32
    mov x2, #1
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr x0, [x29, #24]
    bl _free
    mov x0, #1
    ldp x29, x30, [sp], #48
    ret

// float_arr_new: x0 = size (tagged), d0 = init value (from x1 as raw bits)
//@ let rfarrnew
_rail_float_arr_new:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    asr x2, x0, #1
    str x2, [x29, #16]
    fmov d0, x1
    str d0, [x29, #24]
    lsl x0, x2, #3
    add x0, x0, #8
    bl _rail_chained_malloc
    str x0, [x29, #32]
    ldr x2, [x29, #16]
    str x2, [x0]
    ldr d0, [x29, #24]
    mov x3, #0
    ldr x4, [x29, #32]
.Lfan_loop:
    cmp x3, x2
    b.hs .Lfan_done
    add x5, x3, #1
    str d0, [x4, x5, lsl #3]
    add x3, x3, #1
    b .Lfan_loop
.Lfan_done:
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #48
    ret

// float_arr_get: x0 = arr, x1 = idx (tagged) → raw double bits in x0
//@ let rfarrget
_rail_float_arr_get:
    asr x1, x1, #1
    add x1, x1, #1
    ldr d0, [x0, x1, lsl #3]
    fmov x0, d0
    ret

// float_arr_set: x0 = arr, x1 = idx (tagged), x2 = val (raw double bits) → 1
//@ let rfarrset
_rail_float_arr_set:
    asr x1, x1, #1
    add x1, x1, #1
    fmov d0, x2
    str d0, [x0, x1, lsl #3]
    mov x0, #3
    ret

// float_arr_len: x0 = arr → tagged int
//@ let rfarrlen
_rail_float_arr_len:
    ldr x0, [x0]
    lsl x0, x0, #1
    orr x0, x0, #1
    ret

// float_arr_to_f32_file: x0 = path (str), x1 = arr, x2 = n (tagged)
// Writes n float32 values (converted from f64) to path. Returns 3 (true).
//@ let rfartof32
_rail_float_arr_to_f32_file:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [x29, #48]
    str x21, [x29, #64]
    str x1, [x29, #16]
    asr x2, x2, #1
    str x2, [x29, #24]
    bl _str_unwrap
    mov x1, #0x601
    mov x2, #0x1b6
    movz x16, #5
    movk x16, #0x200, lsl #16
    svc #0x80
    cmp x0, #0
    b.lt .Lf32w_err
    str x0, [x29, #32]
    ldr x21, [x29, #24]
    lsl x0, x21, #2
    bl _rail_chained_malloc
    str x0, [x29, #40]
    mov x19, #0
    ldr x20, [x29, #16]
.Lf32w_loop:
    cmp x19, x21
    b.hs .Lf32w_done
    add x6, x19, #1
    ldr d0, [x20, x6, lsl #3]
    fcvt s0, d0
    ldr x7, [x29, #40]
    lsl x8, x19, #2
    str s0, [x7, x8]
    add x19, x19, #1
    b .Lf32w_loop
.Lf32w_done:
    ldr x0, [x29, #32]
    ldr x1, [x29, #40]
    lsl x2, x21, #2
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr x0, [x29, #32]
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #3
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret
.Lf32w_err:
    mov x0, #1
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret

// float_arr_from_f32_file: x0 = path (str), x1 = arr, x2 = n (tagged)
// Reads n float32 values from path into arr (converted to f64). Returns 3 (true).
//@ let rfarfromf32
_rail_float_arr_from_f32_file:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [x29, #48]
    str x21, [x29, #64]
    str x1, [x29, #16]
    asr x2, x2, #1
    str x2, [x29, #24]
    bl _str_unwrap
    mov x1, #0
    movz x16, #5
    movk x16, #0x200, lsl #16
    svc #0x80
    cmp x0, #0
    b.lt .Lf32r_err
    str x0, [x29, #32]
    ldr x21, [x29, #24]
    lsl x0, x21, #2
    bl _rail_chained_malloc
    str x0, [x29, #40]
    ldr x0, [x29, #32]
    ldr x1, [x29, #40]
    lsl x2, x21, #2
    movz x16, #3
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x19, #0
    ldr x20, [x29, #16]
.Lf32r_loop:
    cmp x19, x21
    b.hs .Lf32r_done
    ldr x7, [x29, #40]
    lsl x8, x19, #2
    ldr s0, [x7, x8]
    fcvt d0, s0
    add x6, x19, #1
    str d0, [x20, x6, lsl #3]
    add x19, x19, #1
    b .Lf32r_loop
.Lf32r_done:
    ldr x0, [x29, #32]
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #3
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret
.Lf32r_err:
    mov x0, #1
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret

//@ cat rshowf, rshowfx, rprintf, rfarrnew, rfarrget, rfarrset, rfarrlen, rfartof32, rfarfromf32
