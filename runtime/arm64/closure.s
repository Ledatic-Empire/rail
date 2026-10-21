// rt_closure: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ let rmap
_rail_map:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    ldr x2, [x1]
    cmp x2, #2
    b.eq .Lmap_nil
    ldr x3, [x1, #8]
    str x3, [x29, #32]
    ldr x3, [x1, #16]
    str x3, [x29, #40]
    ldr x15, [x29, #16]
    ldr x16, [x15, #8]
    ldr x0, [x29, #32]
    blr x16
    str x0, [sp, #-16]!
    ldr x0, [x29, #16]
    ldr x1, [x29, #40]
    bl _rail_map
    mov x1, x0
    ldr x0, [sp], #16
    bl _rail_cons
    ldp x29, x30, [sp], #48
    ret
.Lmap_nil:
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    ldp x29, x30, [sp], #48
    ret

// _rail_join: two-pass linear. Old recursive head+sep+(join sep tail)
// pattern allocated O(n^2) bytes via repeated _rail_str_append calls
// through _rail_chained_malloc (system malloc, never reclaimed). For
// n=100k, 6-char items: 30 GB live. New version walks the list twice
// (compute total length, then memcpy items+seps into one buffer), so
// allocation is O(n * avg_len). Callee-saved: x19=sep_uw, x20=sep_len,
// x21=iter, x22=total->pos, x23=n_items->result_buf.
//@ let rjoin
_rail_join:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x23, [sp, #48]
    ldr x2, [x1]
    cmp x2, #2
    b.eq .Ljoin_empty
    str x0, [sp, #56]
    str x1, [sp, #64]
    bl _str_unwrap
    mov x19, x0
    bl _strlen
    mov x20, x0
    ldr x21, [sp, #64]
    mov x22, #0
    mov x23, #0
.Ljoin_p1_loop:
    ldr x2, [x21]
    cmp x2, #2
    b.eq .Ljoin_p1_done
    ldr x0, [x21, #8]
    bl _str_unwrap
    bl _strlen
    add x22, x22, x0
    add x23, x23, #1
    ldr x21, [x21, #16]
    b .Ljoin_p1_loop
.Ljoin_p1_done:
    sub x4, x23, #1
    madd x22, x4, x20, x22
    add x0, x22, #1
    bl _rail_chained_malloc
    mov x23, x0
    ldr x21, [sp, #64]
    mov x22, #0
    mov x4, #1
.Ljoin_p2_loop:
    ldr x2, [x21]
    cmp x2, #2
    b.eq .Ljoin_p2_done
    cbnz x4, .Ljoin_p2_skip_sep
    add x0, x23, x22
    mov x1, x19
    mov x2, x20
    str x4, [sp, #72]
    str x21, [sp, #80]
    bl _memcpy
    ldr x4, [sp, #72]
    ldr x21, [sp, #80]
    add x22, x22, x20
.Ljoin_p2_skip_sep:
    str x4, [sp, #72]
    str x21, [sp, #80]
    ldr x0, [x21, #8]
    bl _str_unwrap
    str x0, [sp, #56]
    bl _strlen
    str x0, [sp, #88]
    add x0, x23, x22
    ldr x1, [sp, #56]
    ldr x2, [sp, #88]
    bl _memcpy
    ldr x4, [sp, #72]
    ldr x21, [sp, #80]
    ldr x6, [sp, #88]
    add x22, x22, x6
    mov x4, #0
    ldr x21, [x21, #16]
    b .Ljoin_p2_loop
.Ljoin_p2_done:
    add x0, x23, x22
    strb wzr, [x0]
    mov x0, x23
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret
.Ljoin_empty:
    adrp x0, _rail_empty_str@PAGE
    add x0, x0, _rail_empty_str@PAGEOFF
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

// _rail_chars, _rail_split and _rail_str_split read their string through _str_unwrap's
// pointer (16 bytes in) while they allocate the pieces, and the collector counts only a
// pointer to the start of an object, so each also keeps the string itself in its frame.
// Until 2026-09-23 they did not, and a temporary (`split "," (show xs)`) was freed
// mid-split (found by RAIL_GC_STRESS).
//@ let rchars
_rail_chars:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #32]
    bl _str_unwrap
    str x0, [x29, #16]
    bl _strlen
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    ldr x1, [x29, #24]
    bl _rail_chars_build
    ldp x29, x30, [sp], #48
    ret
_rail_chars_build:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    adrp x2, _rail_nil@PAGE
    add x2, x2, _rail_nil@PAGEOFF
    str x2, [x29, #32]
    sub x3, x1, #1
    str x3, [x29, #40]
.Lchars_loop:
    ldr x3, [x29, #40]
    cmp x3, #0
    b.lt .Lchars_done
    mov x0, #2
    bl _rail_chained_malloc
    str x0, [sp, #-16]!
    ldr x1, [x29, #16]
    ldr x3, [x29, #40]
    ldrb w2, [x1, x3]
    strb w2, [x0]
    mov w2, #0
    strb w2, [x0, #1]
    ldr x0, [sp], #16
    bl _rail_wrap_str
    ldr x1, [x29, #32]
    bl _rail_cons
    str x0, [x29, #32]
    ldr x3, [x29, #40]
    sub x3, x3, #1
    str x3, [x29, #40]
    b .Lchars_loop
.Lchars_done:
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #48
    ret

//@ let rsplit
_rail_split:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x1, [x29, #24]
    str x1, [x29, #48]
    bl _str_unwrap
    str x0, [x29, #16]
    ldrb w2, [x0]
    str x2, [x29, #32]
    ldr x0, [x29, #24]
    bl _str_unwrap
    str x0, [x29, #24]
    bl _strlen
    str x0, [x29, #40]
    ldr x0, [x29, #24]
    ldr x1, [x29, #40]
    ldr x2, [x29, #32]
    bl _rail_split_build
    ldp x29, x30, [sp], #64
    ret
_rail_split_build:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    str x2, [x29, #24]
    adrp x3, _rail_nil@PAGE
    add x3, x3, _rail_nil@PAGEOFF
    str x3, [x29, #32]
    str x1, [x29, #40]
    sub x3, x1, #1
    str x3, [x29, #48]
.Lsplit_bk:
    ldr x3, [x29, #48]
    cmp x3, #0
    b.lt .Lsplit_first
    ldr x0, [x29, #16]
    ldrb w4, [x0, x3]
    ldr x5, [x29, #24]
    cmp w4, w5
    b.eq .Lsplit_hit
    sub x3, x3, #1
    str x3, [x29, #48]
    b .Lsplit_bk
.Lsplit_hit:
    ldr x5, [x29, #40]
    sub x6, x5, x3
    sub x6, x6, #1
    str x6, [x29, #56]
    add x0, x6, #1
    bl _rail_chained_malloc
    str x0, [sp, #-16]!
    ldr x1, [x29, #16]
    ldr x3, [x29, #48]
    add x1, x1, x3
    add x1, x1, #1
    ldr x6, [x29, #56]
    mov x4, #0
.Lsplit_cp1:
    cmp x4, x6
    b.ge .Lsplit_cp1d
    ldrb w7, [x1, x4]
    strb w7, [x0, x4]
    add x4, x4, #1
    b .Lsplit_cp1
.Lsplit_cp1d:
    mov w7, #0
    strb w7, [x0, x6]
    ldr x0, [sp], #16
    bl _rail_wrap_str
    ldr x1, [x29, #32]
    bl _rail_cons
    str x0, [x29, #32]
    ldr x3, [x29, #48]
    str x3, [x29, #40]
    sub x3, x3, #1
    str x3, [x29, #48]
    b .Lsplit_bk
.Lsplit_first:
    ldr x6, [x29, #40]
    str x6, [x29, #56]
    add x0, x6, #1
    bl _rail_chained_malloc
    str x0, [sp, #-16]!
    ldr x1, [x29, #16]
    ldr x6, [x29, #56]
    mov x4, #0
.Lsplit_cp2:
    cmp x4, x6
    b.ge .Lsplit_cp2d
    ldrb w7, [x1, x4]
    strb w7, [x0, x4]
    add x4, x4, #1
    b .Lsplit_cp2
.Lsplit_cp2d:
    mov w7, #0
    strb w7, [x0, x6]
    ldr x0, [sp], #16
    bl _rail_wrap_str
    ldr x1, [x29, #32]
    bl _rail_cons
    ldp x29, x30, [sp], #64
    ret

//@ let rfilter
_rail_filter:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    ldr x2, [x1]
    cmp x2, #2
    b.eq .Lfilt_nil
    ldr x3, [x1, #8]
    str x3, [x29, #32]
    ldr x3, [x1, #16]
    str x3, [x29, #40]
    ldr x15, [x29, #16]
    ldr x16, [x15, #8]
    ldr x0, [x29, #32]
    blr x16
    str x0, [sp, #-16]!
    ldr x0, [x29, #16]
    ldr x1, [x29, #40]
    bl _rail_filter
    ldr x1, [sp], #16
    cmp x1, #3
    b.ne .Lfilt_skip
    mov x1, x0
    ldr x0, [x29, #32]
    bl _rail_cons
    ldp x29, x30, [sp], #48
    ret
.Lfilt_skip:
    ldp x29, x30, [sp], #48
    ret
.Lfilt_nil:
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    ldp x29, x30, [sp], #48
    ret

//@ let rfold
_rail_fold:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    str x2, [x29, #32]
    ldr x3, [x2]
    cmp x3, #2
    b.eq .Lfold_done
    ldr x4, [x2, #8]
    str x4, [x29, #40]
    ldr x15, [x29, #16]
    ldr x16, [x15, #8]
    ldr x0, [x29, #24]
    ldr x1, [x29, #40]
    blr x16
    ldr x2, [x29, #32]
    ldr x2, [x2, #16]
    mov x1, x0
    ldr x0, [x29, #16]
    bl _rail_fold
    ldp x29, x30, [sp], #48
    ret
.Lfold_done:
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #48
    ret

//@ let rreverse
_rail_reverse:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    adrp x1, _rail_nil@PAGE
    add x1, x1, _rail_nil@PAGEOFF
    str x1, [x29, #16]
.Lrev_loop:
    ldr x2, [x0]
    cmp x2, #2
    b.eq .Lrev_done
    ldr x1, [x0, #8]
    str x1, [x29, #24]
    ldr x0, [x0, #16]
    str x0, [sp, #-16]!
    ldr x0, [x29, #24]
    ldr x1, [x29, #16]
    bl _rail_cons
    str x0, [x29, #16]
    ldr x0, [sp], #16
    b .Lrev_loop
.Lrev_done:
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

//@ let rrange
_rail_range:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    asr x0, x0, #1
    sub x0, x0, #1
    str x0, [x29, #16]
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    str x0, [x29, #24]
.Lrange_loop:
    ldr x0, [x29, #16]
    cmp x0, #0
    b.lt .Lrange_done
    lsl x0, x0, #1
    orr x0, x0, #1
    ldr x1, [x29, #24]
    bl _rail_cons
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    sub x0, x0, #1
    str x0, [x29, #16]
    b .Lrange_loop
.Lrange_done:
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret

//@ let rcat
_rail_cat:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x1, x0
    adrp x0, _rail_empty_str@PAGE
    add x0, x0, _rail_empty_str@PAGEOFF
    bl _rail_join
    ldp x29, x30, [sp], #16
    ret

//@ cat rmap, rjoin, rcat, rchars, rsplit, rfilter, rfold, rreverse, rrange
