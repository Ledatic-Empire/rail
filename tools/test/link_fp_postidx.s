; tools/test/link_fp_postidx.s: float loads and stores with post-index writeback (t278, 2026-11-04).
; Until the fix `ldr d1, [x0], #8` assembled as `ldr d1, [x0]` in silence (the immediate dropped),
; so a loop read the same double every time; lowbit's attention kernel summed 128 copies of q[0]*k[0].
; sum_f64(src, dst, n): src and dst are Rail float arrays (8-byte length, then doubles);
; dst[0..n) = the running sums of the n doubles of src; returns the last sum truncated to an int.
.text
.p2align 2
_sum_f64:
    add x0, x0, #8
    add x1, x1, #8
    fmov d0, xzr
    mov x3, #0
.Lsf_loop:
    cmp x3, x2
    b.ge .Lsf_done
    ldr d1, [x0], #8
    fadd d0, d0, d1
    str d0, [x1], #8
    add x3, x3, #1
    b .Lsf_loop
.Lsf_done:
    fcvtzs x0, d0
    ret
