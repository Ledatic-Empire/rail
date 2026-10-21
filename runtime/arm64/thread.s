// rt_thread: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// While a spawned thread is not yet joined (_rail_threads_live > 0), _rail_alloc and
// _rail_chained_malloc take _rail_alloc_mutex and _rail_gc returns at once (the collector walks
// only the calling thread's stack; the arena grows instead). Until 2026-09-23 two threads bumped
// the same pointer unlocked and could be handed the same memory.
//@ piece
_rail_spawn_thread:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_lock
    adrp x1, _rail_threads_live@PAGE
    add x1, x1, _rail_threads_live@PAGEOFF
    ldr x2, [x1]
    add x2, x2, #1
    str x2, [x1]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_unlock
    mov x0, #40
    bl _malloc
    str x0, [x29, #32]
    ldr x1, [x29, #16]
    str x1, [x0]
    ldr x1, [x29, #24]
    str x1, [x0, #8]
    str xzr, [x0, #16]
    ldr x3, [x29, #32]
    add x0, x3, #24
    mov x1, #0
    adr x2, _rail_thread_tramp
    mov x3, x3
    bl _pthread_create
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #48
    ret

//@ piece
_rail_thread_tramp:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    ldr x1, [x0, #8]
    ldr x2, [x0]
    tst x2, #1
    b.ne .Ltt_done
    ldr x3, [x2]
    and x3, x3, #0x7fffffffffffffff
    cmp x3, #4
    b.ne .Ltt_fn
    mov x15, x2
    ldr x16, [x15, #8]
    mov x0, x1
    blr x16
    b .Ltt_store
.Ltt_fn:
    mov x0, x1
    blr x2
    b .Ltt_store
.Ltt_done:
    mov x0, #1
.Ltt_store:
    ldr x1, [x29, #16]
    str x0, [x1, #16]
    mov x0, #0
    ldp x29, x30, [sp], #32
    ret

//@ piece
_rail_join_thread:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    ldr x0, [x0, #24]
    mov x1, #0
    bl _pthread_join
    ldr x0, [x29, #16]
    ldr x0, [x0, #16]
    str x0, [x29, #24]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_lock
    adrp x1, _rail_threads_live@PAGE
    add x1, x1, _rail_threads_live@PAGEOFF
    ldr x2, [x1]
    sub x2, x2, #1
    str x2, [x1]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_unlock
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret

//@ piece
_rail_mutex_new:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x0, #64
    bl _malloc
    mov x1, x0
    mov x0, x1
    mov x1, #0
    bl _pthread_mutex_init
    ldp x29, x30, [sp], #16
    ret

