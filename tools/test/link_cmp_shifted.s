// link_cmp_shifted.s: the immediates cmp does hold (t317, 2026-11-19): 0..4095, and a multiple of
// 4096 as the shifted form.
.text
.globl _gt4095
.globl _gt8192
.p2align 2
_gt4095:
    cmp x0, #4095
    cset x0, gt
    ret
_gt8192:
    cmp x0, #8192
    cset x0, gt
    ret
