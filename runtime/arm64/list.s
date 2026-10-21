// rt_list: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// _rail_alloc slow path (bump arena full + GC+free-list can't cover)
// now routes through _rail_chained_malloc for a single source of
// truth on chain layout. Without this, slow-path chunks would use
// the old 8-byte header (user data at chunk[8]) while all other
// chunk producers use the new 16-byte header (alloc_size at chunk[8]),
// and drain would read user data as "size" → munmap with bogus args.
// RAIL_GC_STRESS=N collects on every Nth allocation, however empty the arena, so a test run
// exercises the collector at every point a program allocates (tools/fuzz/gc_stress.py).
//@ let ralloc
_rail_alloc:
    adrp x1, _rail_threads_live@PAGE
    ldr x1, [x1, _rail_threads_live@PAGEOFF]
    cbnz x1, .Lalloc_locked
    b _rail_alloc_core
.Lalloc_locked:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_lock
    ldr x0, [x29, #16]
    bl _rail_alloc_core
    str x0, [x29, #24]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_unlock
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret

_rail_alloc_core:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    adrp x1, _rail_gc_stress@PAGE
    ldr x1, [x1, _rail_gc_stress@PAGEOFF]
    cbnz x1, .Lalloc_stress
.Lalloc_go:
    add x0, x0, #15
    and x0, x0, #-8
    adrp x1, _rail_heap_ptr@PAGE
    add x1, x1, _rail_heap_ptr@PAGEOFF
    ldr x2, [x1]
    add x3, x2, x0
    adrp x4, _rail_heap_end@PAGE
    ldr x4, [x4, _rail_heap_end@PAGEOFF]
    cmp x3, x4
    b.hi .Lalloc_slow
    str x3, [x1]
    ldr x5, [x29, #16]
    str x5, [x2]
    add x0, x2, #8
    ldp x29, x30, [sp], #32
    ret
.Lalloc_stress:
    adrp x2, _rail_gc_stress_left@PAGE
    add x2, x2, _rail_gc_stress_left@PAGEOFF
    ldr x3, [x2]
    subs x3, x3, #1
    b.gt .Lalloc_stress_wait
    str x1, [x2]
    bl _rail_gc
    ldr x0, [x29, #16]
    b .Lalloc_go
.Lalloc_stress_wait:
    str x3, [x2]
    ldr x0, [x29, #16]
    b .Lalloc_go
.Lalloc_slow:
    ldr x0, [x29, #16]
    bl _rail_free_list_alloc
    cbnz x0, .Lalloc_done
    bl _rail_gc
    bl _rail_arena_low
    cbz x0, .Lalloc_fl2
    ldr x0, [x29, #16]
    bl _rail_arena_grow
    cbnz x0, .Lalloc_retry
.Lalloc_fl2:
    ldr x0, [x29, #16]
    bl _rail_free_list_alloc
    cbnz x0, .Lalloc_done
    ldr x0, [x29, #16]
    bl _rail_arena_grow
    cbnz x0, .Lalloc_retry
    adrp x6, _rail_arena_spill_count@PAGE
    add x6, x6, _rail_arena_spill_count@PAGEOFF
    ldr x7, [x6]
    add x7, x7, #1
    str x7, [x6]
    adrp x6, _rail_arena_spill_bytes@PAGE
    add x6, x6, _rail_arena_spill_bytes@PAGEOFF
    ldr x7, [x6]
    ldr x8, [x29, #16]
    add x7, x7, x8
    str x7, [x6]
    adrp x6, _rail_arena_trace_flag@PAGE
    ldr x6, [x6, _rail_arena_trace_flag@PAGEOFF]
    cbz x6, .Lalloc_no_trace
    mov x0, #2
    adrp x1, _rail_arena_trace_msg@PAGE
    add x1, x1, _rail_arena_trace_msg@PAGEOFF
    mov x2, #17
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
.Lalloc_no_trace:
    ldr x0, [x29, #16]
    bl _rail_chained_malloc_core
.Lalloc_done:
    ldp x29, x30, [sp], #32
    ret
.Lalloc_retry:
    ldr x0, [x29, #16]
    b .Lalloc_go

// _rail_arena_grow: x0 = requested size. Moves the arena's end (the next collection point) to
// double the heap, at least far enough for this request, at most the reservation. 1 if it
// moved, 0 at the reservation's end or with no reservation (Linux: the caller spills).
// _rail_arena_low: 1 if the last collection freed under a quarter of the heap.
//@ let rgrow
_rail_arena_grow:
    add x0, x0, #15
    and x0, x0, #-8
    adrp x1, _rail_heap_ptr@PAGE
    ldr x1, [x1, _rail_heap_ptr@PAGEOFF]
    add x2, x1, x0
    adrp x3, _rail_heap_limit@PAGE
    ldr x3, [x3, _rail_heap_limit@PAGEOFF]
    cmp x2, x3
    b.hi .Lgrow_no
    adrp x4, _rail_heap_end@PAGE
    ldr x4, [x4, _rail_heap_end@PAGEOFF]
    adrp x5, _rail_heap_base@PAGE
    ldr x5, [x5, _rail_heap_base@PAGEOFF]
    sub x6, x4, x5
    add x6, x4, x6
    cmp x6, x2
    csel x6, x2, x6, lo
    cmp x6, x3
    csel x6, x3, x6, hi
    adrp x4, _rail_heap_end@PAGE
    str x6, [x4, _rail_heap_end@PAGEOFF]
    adrp x4, _rail_arena_grow_count@PAGE
    add x4, x4, _rail_arena_grow_count@PAGEOFF
    ldr x5, [x4]
    add x5, x5, #1
    str x5, [x4]
    adrp x4, _rail_arena_trace_flag@PAGE
    ldr x4, [x4, _rail_arena_trace_flag@PAGEOFF]
    cbz x4, .Lgrow_yes
    mov x0, #2
    adrp x1, _rail_arena_grow_msg@PAGE
    add x1, x1, _rail_arena_grow_msg@PAGEOFF
    mov x2, #16
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
.Lgrow_yes:
    mov x0, #1
    ret
.Lgrow_no:
    mov x0, #0
    ret

_rail_arena_low:
    adrp x1, _rail_gc_last_freed@PAGE
    ldr x1, [x1, _rail_gc_last_freed@PAGEOFF]
    lsl x1, x1, #2
    adrp x2, _rail_heap_end@PAGE
    ldr x2, [x2, _rail_heap_end@PAGEOFF]
    adrp x3, _rail_heap_base@PAGE
    ldr x3, [x3, _rail_heap_base@PAGEOFF]
    sub x2, x2, x3
    cmp x1, x2
    cset x0, lo
    ret

//@ let rcons
_rail_cons:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    mov x0, #24
    bl _rail_alloc
    mov x1, #1
    str x1, [x0]
    ldr x1, [x29, #16]
    str x1, [x0, #8]
    ldr x1, [x29, #24]
    str x1, [x0, #16]
    ldp x29, x30, [sp], #32
    ret

// Guarded head: safe for nil (returns 0), safe for int/non-list (graceful)
//@ let rhead
_rail_head:
    tst x0, #1
    b.ne .Lhd_int
    ldr x1, [x0]
    cmp x1, #1
    b.ne .Lhd_int
    ldr x0, [x0, #8]
    ret
.Lhd_int:
    mov x0, #1
    ret

// Guarded tail: safe for nil/int (returns nil), safe for non-list
//@ let rtail
_rail_tail:
    tst x0, #1
    b.ne .Ltl_nil
    ldr x1, [x0]
    cmp x1, #1
    b.ne .Ltl_nil
    ldr x0, [x0, #16]
    ret
.Ltl_nil:
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    ret

//@ let rlength
_rail_length:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    tst x0, #1
    b.ne .Llen_zero
    ldr x1, [x0]
    and x1, x1, #0x7fffffffffffffff
    cmp x1, #1
    b.eq .Llen_list
    cmp x1, #2
    b.eq .Llen_zero
    cmp x1, #9
    b.eq .Llen_str9
    bl _strlen
    b .Llen_ret
.Llen_str9:
    ldr x0, [x0, #8]
.Llen_ret:
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret
.Llen_list:
    mov x1, #0
.Llen_loop:
    ldr x2, [x0]
    cmp x2, #2
    b.eq .Llen_done
    ldr x0, [x0, #16]
    add x1, x1, #1
    b .Llen_loop
.Llen_done:
    lsl x0, x1, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret
.Llen_zero:
    mov x0, #1
    ldp x29, x30, [sp], #16
    ret

//@ let rappend
_rail_append:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    tst x0, #1
    b.ne .Lapp_ret2
    ldr x2, [x0]
    cmp x2, #2
    b.eq .Lapp_ret2
    cmp x2, #1
    b.eq .Lapp_list
    bl _rail_str_append
    ldp x29, x30, [sp], #32
    ret
.Lapp_ret2:
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret
.Lapp_list:
    ldr x0, [x29, #16]
    ldr x1, [x0, #8]
    str x1, [sp, #-16]!
    ldr x0, [x0, #16]
    ldr x1, [x29, #24]
    bl _rail_append
    mov x1, x0
    ldr x0, [sp], #16
    bl _rail_cons
    ldp x29, x30, [sp], #32
    ret

//@ cat ralloc, rgrow, rcons, rhead, rtail, rlength, rappend
