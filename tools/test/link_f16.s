// link_f16.s: a half-precision value widened to double through fcvt dD, hN (t279, 2026-11-05).
//   widen_f16(fa, bits): fa[0] = the double of the f16 whose 16 bits are `bits` (fa a Rail float array)
.text
.globl _widen_f16
.p2align 2
_widen_f16:
    fmov s0, w1
    fcvt d0, h0
    str d0, [x0, #8]
    ret
