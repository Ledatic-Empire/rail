// rt_gc_4: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// _rail_gc: main entry point. Walk stack frames, mark, sweep.
// Track A C3: per-frame, look up the owning function's return address in the slot-type
// descriptor table; use its 32-bit bits field to skip slots known to be
// int (00) or float (01). On miss, fall back to the bits = -1 behavior
// (all slots = 11 = scan), which matches the pre-C3 conservative walk.
// x23 holds the current frame's bits register (callee-saved across calls).
//@ piece
_rail_gc:
    adrp x9, _rail_threads_live@PAGE
    ldr x9, [x9, _rail_threads_live@PAGEOFF]
    cbz x9, .Lgc_go
    ret
.Lgc_go:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [x29, #48]
    stp x21, x22, [x29, #64]
    str x23, [x29, #80]
    adrp x0, _rail_gc_count@PAGE
    add x0, x0, _rail_gc_count@PAGEOFF
    ldr x1, [x0]
    add x1, x1, #1
    str x1, [x0]
// The mark stack (512K entries, 4 MB) is allocated on the first collection and kept. Until
// 2026-10-19 every collection took a fresh one from _malloc (over 64 KB: an mmap) and gave it
// to _free, a no-op on macOS, so each collection leaked 4 MB (13 GB in a minute under
// RAIL_GC_STRESS=13). _gc_try_mark doubles it when it fills.
//@ piece
    adrp x1, _gc_mark_stack@PAGE
    ldr x0, [x1, _gc_mark_stack@PAGEOFF]
    cbnz x0, .Lgc_have_stack
//@ piece
    mov x0, #4194304
    bl _malloc
    cbz x0, .Lgc_ret
//@ piece
    adrp x1, _gc_mark_stack@PAGE
    str x0, [x1, _gc_mark_stack@PAGEOFF]
//@ piece
    mov x0, #524288
    adrp x1, _gc_mark_cap@PAGE
    str x0, [x1, _gc_mark_cap@PAGEOFF]
//@ piece
.Lgc_have_stack:
    adrp x1, _gc_mark_top@PAGE
    str xzr, [x1, _gc_mark_top@PAGEOFF]
// Walk stack frames via x29 chain
//@ piece
    mov x19, x29
    str xzr, [x29, #32]
//@ piece
.Lgc_frame_loop:
    cbz x19, .Lgc_sweep
//@ piece
    ldr x20, [x19]
// Which function owns the frame at x19? The return address that points INTO it is the one
// saved in the frame below ([x29, #32] carries it up the walk; 0 for _rail_gc's own frame,
// a miss that scans every slot). The address saved in this frame ([x19, #8]) points into the
// caller, and owns the next frame. Until 2026-09-23 the walk looked this frame up by its own
// saved address, applying the caller's slot bits to it: a runtime function's saved arguments
// (_rail_cons holding a fresh tuple or constructed value) sat in slots the caller calls int,
// were skipped, and the object was swept while still referenced.
// On hit: load 32-bit bits field at offset +16 of the record. On miss: -1.
//@ piece
    ldr x0, [x29, #32]
    ldr x1, [x19, #8]
    str x1, [x29, #32]
    str x19, [x29, #16]
    str x20, [x29, #24]
    bl _gc_lookup_fn_desc
    ldr x19, [x29, #16]
    ldr x20, [x29, #24]
    cbz x0, .Lgc_bits_miss
    ldr w23, [x0, #20]
    b .Lgc_bits_ready
.Lgc_bits_miss:
    mov w23, #-1
.Lgc_bits_ready:
// Scan frame: slots from fp+16 to fp+2048 (or parent frame).
// A frame inside the heap sits on a fiber stack (_rail_spawn carves 64 KB from the arena and
// _rail_await switches sp into it): cap it at _rail_heap_ptr, never at _rail_stack_top. Until
// 2026-10-19 every frame was capped at _rail_stack_top; the arena maps above the main stack
// (0x7000000000 against 0x16f...), so a fiber frame's range collapsed to nothing and every
// object held only by the fiber's frames was swept while live (#116 item 4, t256). A frame on
// the main stack keeps the _rail_stack_top cap, which stops the final frame's walk at the
// real stack top.
//@ piece
    add x21, x19, #16
    add x22, x19, #2048
//@ piece
    adrp x3, _rail_heap_base@PAGE
    ldr x3, [x3, _rail_heap_base@PAGEOFF]
    cmp x19, x3
    b.lo .Lgc_cap_main
    adrp x3, _rail_heap_ptr@PAGE
    ldr x3, [x3, _rail_heap_ptr@PAGEOFF]
    cmp x19, x3
    b.hs .Lgc_cap_main
    cmp x22, x3
    b.ls .Lgc_skip_top_cap
    mov x22, x3
    b .Lgc_skip_top_cap
//@ piece
.Lgc_cap_main:
    adrp x3, _rail_stack_top@PAGE
    ldr x3, [x3, _rail_stack_top@PAGEOFF]
    cbz x3, .Lgc_skip_top_cap
    cmp x22, x3
    b.ls .Lgc_skip_top_cap
    mov x22, x3
.Lgc_skip_top_cap:
// The parent frame caps the range only when it lies above this one. A parent below is the
// frame that called _rail_await on another stack: this frame is the top of its own stack.
//@ piece
    cmp x20, #0
    b.eq .Lgc_scan
    cmp x20, x19
    b.lo .Lgc_scan
    cmp x20, x22
    b.hs .Lgc_scan
    mov x22, x20
// C3: per-slot type dispatch. slot_idx = (x21 - x19) / 8. For slot_idx >= 16,
// fall through to scan (bits field only covers slots 0..15). Extract 2 bits
// at (slot_idx * 2). Values 00 (int) and 01 (float) skip. Values 10 (heap)
// and 11 (fallback) call _gc_try_mark (which still tag-filters).
//@ piece
.Lgc_scan:
    cmp x21, x22
    b.hs .Lgc_scan_done
    sub x4, x21, x19
    lsr x4, x4, #3
    cmp x4, #16
    b.hs .Lgc_scan_trymark
    lsl x4, x4, #1
    lsr w5, w23, w4
    and w5, w5, #3
    cmp w5, #2
    b.lt .Lgc_scan_skip
.Lgc_scan_trymark:
    ldr x0, [x21]
    str x21, [x29, #16]
    str x22, [x29, #24]
    bl _gc_try_mark
    ldr x21, [x29, #16]
    ldr x22, [x29, #24]
.Lgc_scan_skip:
    add x21, x21, #8
    b .Lgc_scan
//@ piece
.Lgc_scan_done:
    bl _gc_drain
    mov x19, x20
    b .Lgc_frame_loop
// Sweep phase
//@ piece
.Lgc_sweep:
    mov x21, #0
//@ piece
    adrp x0, _rail_free_list@PAGE
    str xzr, [x0, _rail_free_list@PAGEOFF]
    adrp x0, _rail_free_16@PAGE
    str xzr, [x0, _rail_free_16@PAGEOFF]
    adrp x0, _rail_free_24@PAGE
    str xzr, [x0, _rail_free_24@PAGEOFF]
// pos = heap start, end = heap_ptr
//@ piece
    adrp x19, _rail_heap_base@PAGE
    ldr x19, [x19, _rail_heap_base@PAGEOFF]
//@ piece
    adrp x20, _rail_heap_ptr@PAGE
    ldr x20, [x20, _rail_heap_ptr@PAGEOFF]
//@ piece
.Lsweep_loop:
    add x1, x19, #8
    cmp x1, x20
    b.hi .Lsweep_done
//@ piece
    ldr x2, [x19]
//@ piece
    add x3, x1, x2
    cmp x3, x20
    b.hi .Lsweep_done
// x1=obj, x2=size. Load tag.
//@ piece
    ldr x4, [x1]
    and x5, x4, #0x7fffffffffffffff
//@ piece
    cmp x5, #1
    b.lo .Lsweep_next
    cmp x5, #9
    b.hi .Lsweep_next
// Marked? Clear mark.
//@ piece
    tbnz x4, #63, .Lsweep_clear
// Unmarked: add to free list. Route exact 16B/24B blocks (the dominant
// cons/box sizes) to their O(1) exact buckets; everything else to the
// first-fit flat list. x1=block (user ptr), x2=size.
//@ piece
    str x2, [x1]
    add x21, x21, x2
// Under RAIL_GC_STRESS the rest of a freed block is filled with 0xDEAD0000, an address in the
// unmapped first 4 GB: anything still reading a block the collector freed faults at once
// instead of reading what happened to be left there.
//@ piece
    adrp x6, _rail_gc_stress@PAGE
    ldr x6, [x6, _rail_gc_stress@PAGEOFF]
    cbz x6, .Lswp_nopoison
    add x6, x1, #16
    add x7, x2, #7
    and x7, x7, #-8
    add x7, x1, x7
    mov x8, #0xdead
    lsl x8, x8, #16
.Lswp_poison:
    cmp x6, x7
    b.hs .Lswp_nopoison
    str x8, [x6]
    add x6, x6, #8
    b .Lswp_poison
.Lswp_nopoison:
//@ piece
    cmp x2, #16
    b.eq .Lswp_f16
    cmp x2, #24
    b.eq .Lswp_f24
    adrp x6, _rail_free_list@PAGE
    add x6, x6, _rail_free_list@PAGEOFF
    ldr x7, [x6]
    str x7, [x1, #8]
    str x1, [x6]
    b .Lsweep_next
//@ piece
.Lswp_f16:
    adrp x6, _rail_free_16@PAGE
    add x6, x6, _rail_free_16@PAGEOFF
    ldr x7, [x6]
    str x7, [x1, #8]
    str x1, [x6]
    b .Lsweep_next
//@ piece
.Lswp_f24:
    adrp x6, _rail_free_24@PAGE
    add x6, x6, _rail_free_24@PAGEOFF
    ldr x7, [x6]
    str x7, [x1, #8]
    str x1, [x6]
    b .Lsweep_next
//@ piece
.Lsweep_clear:
    and x4, x4, #0x7fffffffffffffff
    str x4, [x1]
//@ piece
.Lsweep_next:
    add x2, x2, #7
    and x2, x2, #-8
    add x19, x19, x2
    add x19, x19, #8
    b .Lsweep_loop
//@ piece
.Lsweep_done:
    adrp x0, _rail_gc_last_freed@PAGE
    str x21, [x0, _rail_gc_last_freed@PAGEOFF]
//@ piece
.Lgc_ret:
    ldr x23, [x29, #80]
    ldp x19, x20, [x29, #48]
    ldp x21, x22, [x29, #64]
    ldp x29, x30, [sp], #96
    ret

