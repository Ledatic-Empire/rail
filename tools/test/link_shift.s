// link_shift.s: the shifted register forms of add and sub (t280, 2026-11-05).
//   shr3add(a, b) = a + (b >> 3)      sub2shl(a, b) = a - (b << 2)      asradd(a, b) = a + (b >> 1 as signed)
.text
.globl _shr3add
.globl _sub2shl
.globl _asradd
.p2align 2
_shr3add:
    add x0, x0, x1, lsr #3
    ret
_sub2shl:
    sub x0, x0, x1, lsl #2
    ret
_asradd:
    add x0, x0, x1, asr #1
    ret
