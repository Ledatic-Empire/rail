// link_vec.s: the vector forms lowbit's batched 4-bit kernel and attention kernels use (t281, 2026-11-08): ldp q,
// fadd/fmul/fdiv .2d, dup .2d (lanes 0 and 1), umov x from a lane, str q (offset and post-index), fcvtzs,
// addp .4s, sxtl/sxtl2, scvtf .2d, ld2, trn1/trn2 .2d.
//   vecforms(in, out): in a Rail float array of 5 doubles, out one of 8 (both offset 8, the array's doubles).
//   out0 = (in0 + in2) * in2 + in0   out1 = (in1 + in3) * in3 + in0   out2 = in4
//   out4 = in4 (through ld2 of out0..3 and a lane move)   out5 = out1 (through trn1, dup lane 1, fdiv by in0 = 1, trn2)
//   out6 = 2 * (int in0 + int in2)   out7 = 2 * (int in4 + int in4)   (int32 lanes through addp, sxtl, scvtf; d1 is q1's low lane, in2)
.text
.globl _vecforms
.p2align 2
_vecforms:
    add x0, x0, #8
    add x1, x1, #8
    ldp q0, q1, [x0], #32
    fadd v2.2d, v0.2d, v1.2d
    fmul v2.2d, v2.2d, v1.2d
    dup v3.2d, v0.d[0]
    fadd v2.2d, v2.2d, v3.2d
    umov x3, v2.d[0]
    umov x4, v2.d[1]
    str x3, [x1]
    str x4, [x1, #8]
    ldr d4, [x0]
    str d4, [x1, #16]
    fcvtzs x3, d0
    fcvtzs x4, d1
    fcvtzs x5, d4
    str w3, [x1, #32]
    str w4, [x1, #36]
    str w5, [x1, #40]
    str w5, [x1, #44]
    ldr q5, [x1, #32]
    addp v6.4s, v5.4s, v5.4s
    sxtl v7.2d, v6.2s
    sxtl2 v16.2d, v6.4s
    scvtf v7.2d, v7.2d
    scvtf v16.2d, v16.2d
    fadd v7.2d, v7.2d, v16.2d
    add x7, x1, #48
    str q7, [x7], #16
    ld2 {v17.2d, v18.2d}, [x1], #32
    umov x3, v17.d[1]
    trn1 v19.2d, v17.2d, v18.2d
    dup v20.2d, v19.d[1]
    fdiv v20.2d, v20.2d, v3.2d
    trn2 v21.2d, v20.2d, v20.2d
    umov x4, v21.d[0]
    str x3, [x1]
    str x4, [x1, #8]
    ret
