// rt_fiber: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ let rspawn
_rail_spawn:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, #32
    bl _rail_alloc
    str x0, [x29, #24]
    str xzr, [x0]
    ldr x1, [x29, #16]
    str x1, [x0, #16]
    str xzr, [x0, #24]
    movz x0, #1, lsl #16
    bl _rail_alloc
    add x0, x0, #16, lsl #12
    and x0, x0, #-16
    ldr x1, [x29, #24]
    str x0, [x1, #8]
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret

// _rail_await runs the fiber's closure on its own stack and returns its result. The caller's
// callee-saved registers are saved INSIDE this frame (fp+16 up), where the collector's frame
// walk scans them; pushed below the frame (as until 2026-10-19) they sat between this frame
// and the closure's frame on the other stack, a gap no frame's range covers.
//@ let rawait
_rail_await:
    stp x29, x30, [sp, #-112]!
    mov x29, sp
    stp x19, x20, [x29, #16]
    stp x21, x22, [x29, #32]
    stp x23, x24, [x29, #48]
    stp x25, x26, [x29, #64]
    stp x27, x28, [x29, #80]
    mov x20, x0
    mov x19, sp
    ldr x4, [x20, #8]
    mov sp, x4
    ldr x15, [x20, #16]
    ldr x16, [x15, #8]
    mov x0, #1
    blr x16
    str x0, [x20, #24]
    mov x1, #2
    str x1, [x20]
    mov sp, x19
    ldp x19, x20, [x29, #16]
    ldp x21, x22, [x29, #32]
    ldp x23, x24, [x29, #48]
    ldp x25, x26, [x29, #64]
    ldp x27, x28, [x29, #80]
    ldp x29, x30, [sp], #112
    ret

//@ let ryield
_rail_yield:
    ret

//@ let rinit
_rail_fiber_init:
    ret

// Channel: a cons cell where head = list of values. send appends, recv takes head.
//@ let rchansend
_rail_chan_send:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    ldr x0, [x0, #8]
    str x0, [x29, #32]
    ldr x0, [x29, #24]
    adrp x1, _rail_nil@PAGE
    add x1, x1, _rail_nil@PAGEOFF
    bl _rail_cons
    mov x1, x0
    ldr x0, [x29, #32]
    bl _rail_append
    ldr x1, [x29, #16]
    str x0, [x1, #8]
    mov x0, #1
    ldp x29, x30, [sp], #48
    ret

//@ let rchanrecv
_rail_chan_recv:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x1, [x0, #8]
    ldr x2, [x1]
    cmp x2, #2
    b.eq .Lrecv_empty
    ldr x3, [x1, #8]
    ldr x4, [x1, #16]
    str x4, [x0, #8]
    mov x0, x3
    ldp x29, x30, [sp], #16
    ret
.Lrecv_empty:
    mov x0, #1
    ldp x29, x30, [sp], #16
    ret

//@ cat rspawn, rawait, ryield, rinit, rchansend, rchanrecv
