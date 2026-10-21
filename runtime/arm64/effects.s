// rt_effects: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// Effect handlers: try/catch with setjmp/longjmp
// Handler frame: malloc'd block [prev_handler(8), jmp_buf(25*8=200), error_val(8)]
// _rail_try: x0=body_closure, x1=handler_closure → result
// If body calls error, longjmp unwinds to handler
//@ let rtry
_rail_try:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    mov x0, #216
    bl _malloc
    str x0, [x29, #32]
    adrp x1, _rail_handler_top@PAGE
    add x1, x1, _rail_handler_top@PAGEOFF
    ldr x2, [x1]
    str x2, [x0]
    str x0, [x1]
    add x0, x0, #8
    bl _setjmp
    cbnz x0, .Ltry_caught
    ldr x15, [x29, #16]
    ldr x16, [x15, #8]
    mov x0, #1
    blr x16
    str x0, [x29, #40]
    ldr x0, [x29, #32]
    ldr x1, [x0]
    adrp x2, _rail_handler_top@PAGE
    add x2, x2, _rail_handler_top@PAGEOFF
    str x1, [x2]
    ldr x0, [x29, #32]
    bl _free
    ldr x0, [x29, #40]
    ldp x29, x30, [sp], #64
    ret
.Ltry_caught:
    ldr x0, [x29, #32]
    ldr x3, [x0, #208]
    str x3, [x29, #48]
    ldr x1, [x0]
    adrp x2, _rail_handler_top@PAGE
    add x2, x2, _rail_handler_top@PAGEOFF
    str x1, [x2]
    ldr x0, [x29, #32]
    bl _free
    ldr x15, [x29, #24]
    ldr x16, [x15, #8]
    ldr x0, [x29, #48]
    blr x16
    ldp x29, x30, [sp], #64
    ret

// _rail_raise: x0=error_msg_string → noreturn (longjmp to handler)
//@ let rraise
_rail_raise:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    adrp x1, _rail_handler_top@PAGE
    add x1, x1, _rail_handler_top@PAGEOFF
    ldr x2, [x1]
    cbz x2, .Lraise_nohandler
    ldr x0, [x29, #16]
    str x0, [x2, #208]
    add x0, x2, #8
    mov x1, #1
    bl _longjmp
.Lraise_nohandler:
    mov x0, #16
    bl _rail_alloc
    mov x1, #8
    str x1, [x0]
    ldr x1, [x29, #16]
    str x1, [x0, #8]
    ldp x29, x30, [sp], #32
    ret

//@ cat rtry, rraise
