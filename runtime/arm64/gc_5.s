// rt_gc_5: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// Precise-GC Track A (C2): binary-search a PC against the per-function
// descriptor table emitted by compile_func. Contract:
//   input:  x0 = PC to resolve
//   output: x0 = pointer to 32-byte record (fn_start, fn_end, nslots, bits, pad)
//           or 0 if PC is outside every recorded fn range
// Clobbers x1-x6. Caller saves x29/x30 via the normal prologue.
// Records are sorted by fn_start_pc (monotone compilation order).
//@ piece
_gc_lookup_fn_desc:
//@ piece
    adrp x1, _gc_desc_table_start@PAGE
    add  x1, x1, _gc_desc_table_start@PAGEOFF
//@ piece
    adrp x2, _gc_desc_table_end@PAGE
    add  x2, x2, _gc_desc_table_end@PAGEOFF
//@ piece
.Llf_loop:
//@ piece
    cmp  x1, x2
    b.hs .Llf_miss
// mid = lo + ((hi - lo) / 64) * 32  (rounds DOWN to 32-byte record boundary)
//@ piece
    sub  x3, x2, x1
    lsr  x3, x3, #6
    lsl  x3, x3, #5
    add  x4, x1, x3
//@ piece
    ldr  x5, [x4]
    ldr  x6, [x4, #8]
//@ piece
    cmp  x0, x5
    b.lo .Llf_left
    cmp  x0, x6
    b.hs .Llf_right
//@ piece
    mov  x0, x4
    ret
//@ piece
.Llf_left:
    mov  x2, x4
    b    .Llf_loop
//@ piece
.Llf_right:
    add  x1, x4, #32
    b    .Llf_loop
//@ piece
.Llf_miss:
    mov  x0, #0
    ret

