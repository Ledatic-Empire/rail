// rt_gc_1: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// Free list globals + mark stack globals
//@ piece
.data
.global _rail_free_list
_rail_free_list:
    .quad 0
_rail_free_16:
    .quad 0
_rail_free_24:
    .quad 0
//@ piece
_gc_mark_stack:
    .quad 0
_gc_mark_top:
    .quad 0
_gc_mark_cap:
    .quad 0
//@ piece
_rail_malloc_ptr:
    .quad 0
_rail_malloc_end:
    .quad 0
//@ piece
_rail_malloc_chain:
    .quad 0
_rail_chain_mark:
    .quad 0
// _rail_stack_top: initial SP captured at main entry. GC uses this as
// an upper bound when scanning the top frame, so fp+2048 default can't
// read past the real stack top (symptom: EXC_BAD_ACCESS in .Lgc_scan
// when env var count made main_fp near the stack top page, see
// docs/gc-phase0-findings.md).
//@ piece
_rail_stack_top:
    .quad 0
// Small-block free list: 12 power-of-two size classes (32B, 64B, 128B, ...
// up to 65536B). Heads pushed by _rail_malloc_chain_drain when sub-64KB
// chunks are evicted from the chain; popped by _rail_chained_malloc on
// matching requests. This turns _free-no-op (for small blocks) into a
// recycling pool, fixing the 3 MB/step leak documented in
// docs/plans/1D4_MEMORY_LEAK.md.
//@ piece
_rail_small_fl:
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
// Phase 1d.4 diagnostic counters. _rail_small_fl_miss[i] increments each
// time _rail_chained_malloc falls through to _malloc for class i (empty
// free list). _rail_munmap_count increments each time drain munmaps a
// >64KB chunk. Exposed to Rail via alloc_stats_snapshot builtin →
// _rail_alloc_stats, to diagnose the residual ~2 MB/step after the
// small-block fix landed.
//@ piece
_rail_small_fl_miss:
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
_rail_munmap_count:
    .quad 0
_rail_mmap_large_count:
    .quad 0
_rail_arena_spill_count:
    .quad 0
_rail_gc_count:
    .quad 0
_rail_arena_spill_bytes:
    .quad 0
_rail_arena_trace_flag:
    .quad 0
_rail_gc_stress:
    .quad 0
_rail_gc_stress_left:
    .quad 0
_rail_gc_last_freed:
    .quad 0
_rail_arena_grow_count:
    .quad 0
_rail_threads_live:
    .quad 0
.p2align 3
_rail_alloc_mutex:
    .quad 850045863
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
    .quad 0
_rail_arena_trace_msg:
    .asciz "rail_arena_spill\n"
_rail_arena_grow_msg:
    .asciz "rail_arena_grow\n"
_gc_mark_msg:
    .asciz "rail: gc mark stack exhausted\n"
.text

// rail_free_list_alloc: first-fit search. x0=size, returns ptr or 0
// Exact-size buckets (16B, 24B) checked first, O(1) pop; fall through to
// the first-fit flat list on miss. Sweep keeps 16/24B blocks OUT of the
// flat list, so the first-fit scan below only sees larger/odd sizes.
//@ piece
_rail_free_list_alloc:
    cmp x0, #16
    b.ne .Lfla_t24
    adrp x4, _rail_free_16@PAGE
    add x4, x4, _rail_free_16@PAGEOFF
    ldr x2, [x4]
    cbz x2, .Lfla_main
    ldr x3, [x2, #8]
    str x3, [x4]
    mov x0, x2
    ret
.Lfla_t24:
    cmp x0, #24
    b.ne .Lfla_main
    adrp x4, _rail_free_24@PAGE
    add x4, x4, _rail_free_24@PAGEOFF
    ldr x2, [x4]
    cbz x2, .Lfla_main
    ldr x3, [x2, #8]
    str x3, [x4]
    mov x0, x2
    ret
.Lfla_main:
    adrp x1, _rail_free_list@PAGE
    add x1, x1, _rail_free_list@PAGEOFF
//@ piece
.Lfla_loop:
    ldr x2, [x1]
    cbz x2, .Lfla_fail
    ldr x3, [x2]
    cmp x3, x0
    b.ge .Lfla_found
    add x1, x2, #8
    b .Lfla_loop
//@ piece
.Lfla_found:
    ldr x3, [x2, #8]
    str x3, [x1]
    mov x0, x2
    ret
//@ piece
.Lfla_fail:
    mov x0, #0
    ret

// rail_free_list_clear
//@ piece
_rail_free_list_clear:
    adrp x0, _rail_free_list@PAGE
    str xzr, [x0, _rail_free_list@PAGEOFF]
    adrp x0, _rail_free_16@PAGE
    str xzr, [x0, _rail_free_16@PAGEOFF]
    adrp x0, _rail_free_24@PAGE
    str xzr, [x0, _rail_free_24@PAGEOFF]
    ret

// rail_chained_malloc: libc malloc + prepend to the chain. Used by
// _rail_float_arr_new (and any other runtime site that needs a bigger
// block than the 512MB bump arena can always fit). Returns user ptr
// one link past the chunk head, so callers see the familiar layout.
// The chunk[0] slot holds the next-link for arena_reset to walk.
// Chunk layout (v2): [next_link(8)] [alloc_size(8)] [user_data(N)]
//                    ^chunk                          ^user_ptr = chunk + 16
//
// alloc_size is the total byte count passed to _malloc, so drain can
// munmap the exact region. Without this header Rail's `_free` stub is
// a no-op and large mmap'd pages never return to OS, the cause of
// the 38GB peak footprint at 500 steps on seq=512 chunked training.
// Small requests (≤64KB) round up to a power-of-two size class and try
// the per-class free list first; misses fall through to _malloc with the
// class size. Large requests (>64KB) go straight to _malloc with the
// aligned total, same as pre-fix behavior. Stored alloc_size at [chunk,#8]
// is always the actual block size (class_bytes for small, aligned total
// for large) so drain's munmap path is unchanged.
//@ piece
_rail_chained_malloc:
    adrp x1, _rail_threads_live@PAGE
    ldr x1, [x1, _rail_threads_live@PAGEOFF]
    cbnz x1, .Lcm_locked
    b _rail_chained_malloc_core
.Lcm_locked:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_lock
    ldr x0, [x29, #16]
    bl _rail_chained_malloc_core
    str x0, [x29, #24]
    adrp x0, _rail_alloc_mutex@PAGE
    add x0, x0, _rail_alloc_mutex@PAGEOFF
    bl _pthread_mutex_unlock
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret

_rail_chained_malloc_core:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    add x0, x0, #31
    and x0, x0, #-16
    cmp x0, #32
    b.hs .Lcm_k32
    mov x0, #32
.Lcm_k32:
    cmp x0, #65536
    b.hi .Lcm_alloc_direct
    sub x3, x0, #1
    clz x3, x3
    mov x4, #64
    sub x3, x4, x3
    sub x2, x3, #5
    mov x0, #1
    lsl x0, x0, x3
    adrp x4, _rail_small_fl@PAGE
    add x4, x4, _rail_small_fl@PAGEOFF
    add x5, x4, x2, lsl #3
    ldr x6, [x5]
    cbz x6, .Lcm_miss
    ldr x7, [x6]
    str x7, [x5]
    str x0, [x29, #24]
    mov x0, x6
    b .Lcm_link
.Lcm_miss:
    adrp x8, _rail_small_fl_miss@PAGE
    add x8, x8, _rail_small_fl_miss@PAGEOFF
    add x8, x8, x2, lsl #3
    ldr x9, [x8]
    add x9, x9, #1
    str x9, [x8]
.Lcm_alloc_direct:
    str x0, [x29, #24]
    bl _malloc
.Lcm_link:
    ldr x2, [x29, #24]
    str x2, [x0, #8]
    adrp x1, _rail_malloc_chain@PAGE
    add x1, x1, _rail_malloc_chain@PAGEOFF
    ldr x2, [x1]
    str x2, [x0]
    str x0, [x1]
    add x0, x0, #16
    ldp x29, x30, [sp], #32
    ret

// rail_malloc_chain_drain: walk the chain down to _rail_chain_mark,
// release each chunk. Preserves anything allocated before the
// outstanding arena_mark (e.g. weights created in main). Rail's `_free`
// is a stub (ret), so for large chunks that came from `_malloc`'s mmap
// path (size > 64KB) we issue munmap directly (darwin svc #73). Small
// chunks live inside the _rail_malloc_ptr bump region and can't be
// individually returned; we fall through to `_free` (no-op) for those.
// The 64KB cutoff matches `_malloc`'s internal b.hi .Lmal_large test.
//@ piece
_rail_malloc_chain_drain:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x19, [x29, #16]
    str x20, [x29, #24]
    adrp x19, _rail_malloc_chain@PAGE
    add x19, x19, _rail_malloc_chain@PAGEOFF
    adrp x20, _rail_chain_mark@PAGE
    add x20, x20, _rail_chain_mark@PAGEOFF
.Lmdrn_loop:
    ldr x0, [x19]
    ldr x1, [x20]
    cmp x0, x1
    b.eq .Lmdrn_done
    cbz x0, .Lmdrn_done
    ldr x2, [x0]
    str x2, [x19]
    ldr x3, [x0, #8]
    cmp x3, #65536
    b.ls .Lmdrn_small
    str x0, [x29, #32]
    str x3, [x29, #40]
    mov x1, x3
    mov x16, #73
    movk x16, #0x200, lsl #16
    svc #0x80
    adrp x4, _rail_munmap_count@PAGE
    add x4, x4, _rail_munmap_count@PAGEOFF
    ldr x5, [x4]
    add x5, x5, #1
    str x5, [x4]
    b .Lmdrn_loop
.Lmdrn_small:
    sub x4, x3, #1
    clz x4, x4
    mov x5, #64
    sub x4, x5, x4
    sub x4, x4, #5
    adrp x5, _rail_small_fl@PAGE
    add x5, x5, _rail_small_fl@PAGEOFF
    add x5, x5, x4, lsl #3
    ldr x6, [x5]
    str x6, [x0]
    str x0, [x5]
    b .Lmdrn_loop
.Lmdrn_done:
    ldr x20, [x29, #24]
    ldr x19, [x29, #16]
    ldp x29, x30, [sp], #64
    ret

// _rail_alloc_stats: build a 14-element Rail int array (tag 7) holding
// [miss_count[0..11], munmap_count, mmap_large_count]. Allocates 128 bytes
// (=16 hdr + 14*8 elems) via _rail_alloc, writes tag+length, then copies
// each raw counter as a tagged int ((raw<<1)|1). Used by the
// alloc_stats_snapshot builtin. mmap_large_count lets us confirm whether
// drain's munmap count matches the large-path mmap count, if equal, no
// leak in the large-chunk path; any growth is macOS VA accounting.
//@ piece
_rail_alloc_stats:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov x0, #176
    bl _rail_alloc
    str x0, [x29, #16]
    mov x1, #7
    str x1, [x0]
    mov x1, #17
    str x1, [x0, #8]
    adrp x2, _rail_small_fl_miss@PAGE
    add x2, x2, _rail_small_fl_miss@PAGEOFF
    mov x3, #0
.Las_loop:
    cmp x3, #12
    b.hs .Las_munmap
    ldr x4, [x2, x3, lsl #3]
    lsl x4, x4, #1
    orr x4, x4, #1
    add x5, x3, #2
    ldr x6, [x29, #16]
    str x4, [x6, x5, lsl #3]
    add x3, x3, #1
    b .Las_loop
.Las_munmap:
    adrp x2, _rail_munmap_count@PAGE
    add x2, x2, _rail_munmap_count@PAGEOFF
    ldr x4, [x2]
    lsl x4, x4, #1
    orr x4, x4, #1
    mov x5, #14
    ldr x6, [x29, #16]
    str x4, [x6, x5, lsl #3]
    adrp x2, _rail_mmap_large_count@PAGE
    add x2, x2, _rail_mmap_large_count@PAGEOFF
    ldr x4, [x2]
    lsl x4, x4, #1
    orr x4, x4, #1
    mov x5, #15
    ldr x6, [x29, #16]
    str x4, [x6, x5, lsl #3]
    adrp x2, _rail_arena_spill_count@PAGE
    add x2, x2, _rail_arena_spill_count@PAGEOFF
    ldr x4, [x2]
    lsl x4, x4, #1
    orr x4, x4, #1
    mov x5, #16
    ldr x6, [x29, #16]
    str x4, [x6, x5, lsl #3]
    adrp x2, _rail_gc_count@PAGE
    add x2, x2, _rail_gc_count@PAGEOFF
    ldr x4, [x2]
    lsl x4, x4, #1
    orr x4, x4, #1
    mov x5, #17
    ldr x6, [x29, #16]
    str x4, [x6, x5, lsl #3]
    adrp x2, _rail_arena_spill_bytes@PAGE
    add x2, x2, _rail_arena_spill_bytes@PAGEOFF
    ldr x4, [x2]
    lsl x4, x4, #1
    orr x4, x4, #1
    mov x5, #18
    ldr x6, [x29, #16]
    str x4, [x6, x5, lsl #3]
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

