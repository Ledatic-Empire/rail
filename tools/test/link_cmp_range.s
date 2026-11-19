// link_cmp_range.s: an immediate cmp cannot hold (t316, 2026-11-19). 5000 is neither 0..4095 nor a
// multiple of 4096; the assembler used to keep the low 12 bits and compare against 904.
.text
.globl _gt5000
.p2align 2
_gt5000:
    cmp x0, #5000
    b.gt .Lyes
    mov x0, #0
    ret
.Lyes:
    mov x0, #1
    ret
