// rt_str_gc: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// _str_unwrap: if x0 points to tagged string [9,len,bytes...], return x0+16. Else return x0 as-is.
//@ let unwrap
_str_unwrap:
    tst x0, #1
    b.ne .Luw_ret
    adrp x1, _rail_heap_base@PAGE
    ldr x1, [x1, _rail_heap_base@PAGEOFF]
    cmp x0, x1
    b.lo .Luw_ret
    adrp x1, _rail_heap_ptr@PAGE
    ldr x1, [x1, _rail_heap_ptr@PAGEOFF]
    cmp x0, x1
    b.hs .Luw_ret
    ldr x1, [x0]
    cmp x1, #9
    b.ne .Luw_ret
    add x0, x0, #16
.Luw_ret:
    ret

// _rail_wrap_str: x0=raw C string. Copy to GC heap as tagged string [9,len,bytes]. Returns tagged ptr.
//@ let wrap
_rail_wrap_str:
    tst x0, #1
    b.ne .Lwrap_do
    adrp x1, _rail_heap_base@PAGE
    ldr x1, [x1, _rail_heap_base@PAGEOFF]
    cmp x0, x1
    b.lo .Lwrap_do
    adrp x1, _rail_heap_ptr@PAGE
    ldr x1, [x1, _rail_heap_ptr@PAGEOFF]
    cmp x0, x1
    b.hs .Lwrap_do
    ldr x1, [x0]
    cmp x1, #9
    b.eq .Lwrap_noop
.Lwrap_do:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    bl _strlen
    str x0, [x29, #24]
    add x0, x0, #17
    bl _rail_alloc
    str x0, [x29, #32]
    mov x1, #9
    str x1, [x0]
    ldr x1, [x29, #24]
    str x1, [x0, #8]
    add x0, x0, #16
    ldr x1, [x29, #16]
    ldr x2, [x29, #24]
    add x2, x2, #1
.Lwrap_cp:
    cbz x2, .Lwrap_done
    ldrb w3, [x1], #1
    strb w3, [x0], #1
    sub x2, x2, #1
    b .Lwrap_cp
.Lwrap_done:
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #48
.Lwrap_noop:
    ret

//@ cat unwrap, wrap
