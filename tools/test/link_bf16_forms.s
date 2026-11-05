; tools/test/link_bf16_forms.s: the scalar forms lowbit's qmatvec4 kernel reads a bf16 scale with
; (t276, 2026-11-04): ldrh post-index, lsl w #16, fmov s, fcvt d, scvtf d from a w register.
; Two bf16 values at x0, a 32-bit signed int in w1 (the upper half of x1 is garbage on purpose:
; scvtf's w form must read 32 bits), the product truncated to an int out.
.text
.p2align 2
_bf16_forms:
    ldrh w2, [x0], #2
    lsl w2, w2, #16
    fmov s0, w2
    fcvt d0, s0
    ldrh w2, [x0], #2
    lsl w2, w2, #16
    fmov s1, w2
    fcvt d1, s1
    fmul d0, d0, d1
    movz x1, #65533
    movk x1, #65535, lsl #16
    movk x1, #4660, lsl #32
    scvtf d1, w1
    fmul d0, d0, d1
    fcvtzs x0, d0
    ret
