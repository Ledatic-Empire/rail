// rt_args: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ literal
_rail_args:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    adrp x0, _rail_argc@PAGE
    ldr x0, [x0, _rail_argc@PAGEOFF]
    adrp x1, _rail_argv@PAGE
    ldr x1, [x1, _rail_argv@PAGEOFF]
    str x0, [x29, #16]
    str x1, [x29, #24]
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    str x0, [x29, #32]
    ldr x0, [x29, #16]
    sub x0, x0, #1
    str x0, [x29, #16]
.Largs_lp:
    ldr x0, [x29, #16]
    cmp x0, #0
    b.lt .Largs_dn
    ldr x1, [x29, #24]
    ldr x0, [x1, x0, lsl #3]
    str x0, [x29, #40]
    bl _strlen
    add x0, x0, #1
    bl _rail_chained_malloc
    str x0, [x29, #48]
    ldr x1, [x29, #40]
    bl _strcpy
    ldr x0, [x29, #48]
    bl _rail_wrap_str
    ldr x1, [x29, #32]
    bl _rail_cons
    str x0, [x29, #32]
    ldr x0, [x29, #16]
    sub x0, x0, #1
    str x0, [x29, #16]
    b .Largs_lp
.Largs_dn:
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #64
    ret

