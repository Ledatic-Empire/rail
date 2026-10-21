// rt_core: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ let req
_rail_eq:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    tst x1, #1
    b.eq .Lreq_heap
    cmp x1, x0
    cset x0, eq
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lreq_heap:
    cbz x1, .Lreq_raw_cmp
    cbz x0, .Lreq_raw_cmp
    tst x0, #1
    b.ne .Lreq_mismatch
    lsr x2, x1, #47
    cbnz x2, .Lreq_fl
    cmp x1, #4095
    b.ls .Lreq_fl
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.eq .Lreq_fl
    str x0, [x29, #16]
    str x1, [x29, #24]
    bl _rail_eq_heap
    cmp x0, #2
    b.ne .Lreq_bool
    ldr x0, [x29, #16]
    ldr x1, [x29, #24]
    str x0, [x29, #16]
    mov x0, x1
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    mov x1, x0
    ldr x0, [x29, #24]
    bl _strcmp
    cmp x0, #0
    cset x0, eq
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lreq_bool:
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lreq_raw_cmp:
    cmp x1, x0
    cset x0, eq
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lreq_mismatch:
    mov x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lreq_fl:
    bl _rail_fval1
    bl _rail_fval
    fcmp d1, d0
    cset x0, eq
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret

//@ let rne
_rail_ne:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_eq
    mov x1, #4
    sub x0, x1, x0
    ldp x29, x30, [sp], #16
    ret

// _rail_eq_heap a b: structural equality of two heap values: 1 equal, 0 not, 2 when neither
// is a container (the caller compares them as strings). Cons cells (1) compare heads by
// recursion and tails by iteration; nil (2) equals nil; tuples (3, [3, n, elems]) compare
// lengths and elements; constructed values (5, [5, id, fields]) compare constructor ids and
// the fields _rail_ctor_arity says they have. Closures (4), arrays (7) and errors (8) are equal
// only to themselves. Until 2026-09-23 these all went to strcmp, which compared header bytes:
// `Some 1 == Some 2` and `(1, 2) == (3, 4)` were true.
//@ let reqh
_rail_eq_heap:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    cmp x0, x1
    b.eq .Leqh_true
    ldr x2, [x0]
    and x2, x2, #0x7fffffffffffffff
    ldr x3, [x1]
    and x3, x3, #0x7fffffffffffffff
    cmp x2, #4
    b.eq .Leqh_false
    cmp x2, #7
    b.eq .Leqh_false
    cmp x2, #8
    b.eq .Leqh_false
    cmp x2, #5
    b.hi .Leqh_nota
    cbz x2, .Leqh_nota
    cmp x3, x2
    b.ne .Leqh_false
    cmp x2, #2
    b.eq .Leqh_true
    cmp x2, #1
    b.eq .Leqh_cons
    cmp x2, #3
    b.eq .Leqh_tuple
    ldr x4, [x0, #8]
    ldr x5, [x1, #8]
    cmp x4, x5
    b.ne .Leqh_false
    adrp x6, _rail_ctor_count@PAGE
    ldr x6, [x6, _rail_ctor_count@PAGEOFF]
    cmp x4, x6
    b.hs .Leqh_true
    adrp x6, _rail_ctor_arity@PAGE
    add x6, x6, _rail_ctor_arity@PAGEOFF
    ldr x5, [x6, x4, lsl #3]
    b .Leqh_fields
.Leqh_tuple:
    ldr x4, [x0, #8]
    ldr x5, [x1, #8]
    cmp x4, x5
    b.ne .Leqh_false
.Leqh_fields:
    str x5, [x29, #40]
    str xzr, [x29, #32]
.Leqh_floop:
    ldr x4, [x29, #32]
    ldr x5, [x29, #40]
    cmp x4, x5
    b.hs .Leqh_true
    add x4, x4, #2
    ldr x0, [x29, #16]
    ldr x0, [x0, x4, lsl #3]
    ldr x1, [x29, #24]
    ldr x1, [x1, x4, lsl #3]
    bl _rail_eq
    cmp x0, #3
    b.ne .Leqh_false
    ldr x4, [x29, #32]
    add x4, x4, #1
    str x4, [x29, #32]
    b .Leqh_floop
.Leqh_cons:
    ldr x0, [x29, #16]
    ldr x0, [x0, #8]
    ldr x1, [x29, #24]
    ldr x1, [x1, #8]
    bl _rail_eq
    cmp x0, #3
    b.ne .Leqh_false
    ldr x0, [x29, #16]
    ldr x0, [x0, #16]
    ldr x1, [x29, #24]
    ldr x1, [x1, #16]
    str x0, [x29, #16]
    str x1, [x29, #24]
    cmp x0, x1
    b.eq .Leqh_true
    tst x0, #1
    b.ne .Leqh_tail
    tst x1, #1
    b.ne .Leqh_tail
    cbz x0, .Leqh_tail
    cbz x1, .Leqh_tail
    ldr x2, [x0]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #1
    b.ne .Leqh_tail
    ldr x3, [x1]
    and x3, x3, #0x7fffffffffffffff
    cmp x3, #1
    b.eq .Leqh_cons
.Leqh_tail:
    bl _rail_eq
    cmp x0, #3
    b.ne .Leqh_false
.Leqh_true:
    mov x0, #1
    ldp x29, x30, [sp], #64
    ret
.Leqh_false:
    mov x0, #0
    ldp x29, x30, [sp], #64
    ret
.Leqh_nota:
    mov x0, #2
    ldp x29, x30, [sp], #64
    ret

//@ let radd
_rail_add:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    tst x1, #1
    b.eq .Ladd_heap
    tst x0, #1
    b.eq .Ladd_fl
    asr x1, x1, #1
    asr x0, x0, #1
    add x0, x1, x0
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #16
    ret
.Ladd_heap:
    tst x0, #1
    b.ne .Ladd_fl
    lsr x2, x1, #47
    cbnz x2, .Ladd_fl
    cmp x1, #4095
    b.ls .Ladd_fl
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.eq .Ladd_fl
    mov x2, x0
    mov x0, x1
    mov x1, x2
    bl _rail_str_append
    ldp x29, x30, [sp], #16
    ret
.Ladd_fl:
    bl _rail_fval1
    bl _rail_fval
    fadd d0, d1, d0
    mov x0, #16
    bl _rail_alloc
    mov x1, #6
    str x1, [x0]
    str d0, [x0, #8]
    ldp x29, x30, [sp], #16
    ret

//@ let rprint
_rail_print:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    tst x0, #1
    b.eq .Lprnt_heap
    asr x0, x0, #1
    mov x1, #0
    cmp x0, #0
    b.ge .Lpi_pos
    neg x0, x0
    mov x1, #1
.Lpi_pos:
    str x1, [x29, #48]
    mov x2, #0
    mov x3, #10
    add x4, x29, #16
.Lpi_div:
    udiv x5, x0, x3
    msub x6, x5, x3, x0
    add x6, x6, #48
    str x6, [sp, #-16]!
    add x2, x2, #1
    mov x0, x5
    cbnz x0, .Lpi_div
    cbz x2, .Lpi_zero
    mov x7, #0
    ldr x1, [x29, #48]
    cbz x1, .Lpi_nosign
    mov w1, #45
    strb w1, [x4, x7]
    add x7, x7, #1
.Lpi_nosign:
.Lpi_rev:
    ldr x6, [sp], #16
    strb w6, [x4, x7]
    add x7, x7, #1
    sub x2, x2, #1
    cbnz x2, .Lpi_rev
    mov w1, #10
    strb w1, [x4, x7]
    add x7, x7, #1
    mov x0, #1
    mov x1, x4
    mov x2, x7
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    b .Lprnt_done
.Lpi_zero:
    mov w0, #48
    strb w0, [x4]
    mov w0, #10
    strb w0, [x4, #1]
    mov x0, #1
    mov x1, x4
    mov x2, #2
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    b .Lprnt_done
.Lprnt_heap:
    ldr x1, [x0]
    and x1, x1, #0x7fffffffffffffff
    cmp x1, #6
    b.eq .Lprnt_float
    bl _str_unwrap
    str x0, [x29, #16]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #16]
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov w0, #10
    strb w0, [x29, #24]
    mov x0, #1
    add x1, x29, #24
    mov x2, #1
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    b .Lprnt_done
.Lprnt_float:
    ldr d0, [x0, #8]
    str d0, [x29, #16]
    mov x0, #32
    bl _malloc
    str x0, [x29, #24]
    ldr d0, [x29, #16]
    str d0, [sp, #-16]!
    ldr x0, [x29, #24]
    mov x1, #32
    adrp x2, _fmt_gbare@PAGE
    add x2, x2, _fmt_gbare@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #24]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #24]
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov w0, #10
    strb w0, [x29, #32]
    mov x0, #1
    add x1, x29, #32
    mov x2, #1
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr x0, [x29, #24]
    bl _free
.Lprnt_done:
    mov x0, #1
    ldp x29, x30, [sp], #64
    ret

//@ let rshow
_rail_show:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl _rail_show_inner
    bl _rail_wrap_str
    ldp x29, x30, [sp], #16
    ret

_rail_show_inner:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    tst x0, #1
    b.eq .Lshow_heap
    asr x0, x0, #1
    str x0, [x29, #16]
    mov x0, #24
    bl _rail_chained_malloc
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    ldr x1, [x29, #24]
    mov x6, #0
    cmp x0, #0
    b.ge .Lsi_pos
    neg x0, x0
    mov w7, #45
    strb w7, [x1, x6]
    add x6, x6, #1
.Lsi_pos:
    str x6, [x29, #16]
    mov x2, #0
    mov x3, #10
.Lsi_div:
    udiv x4, x0, x3
    msub x5, x4, x3, x0
    add x5, x5, #48
    str x5, [sp, #-16]!
    add x2, x2, #1
    mov x0, x4
    cbnz x0, .Lsi_div
    cbz x2, .Lsi_zero
    ldr x6, [x29, #16]
    ldr x1, [x29, #24]
.Lsi_rev:
    ldr x5, [sp], #16
    strb w5, [x1, x6]
    add x6, x6, #1
    sub x2, x2, #1
    cbnz x2, .Lsi_rev
    mov w5, #0
    strb w5, [x1, x6]
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret
.Lsi_zero:
    ldr x6, [x29, #16]
    ldr x1, [x29, #24]
    mov w0, #48
    strb w0, [x1, x6]
    add x6, x6, #1
    mov w0, #0
    strb w0, [x1, x6]
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret
.Lshow_heap:
    ldr x1, [x0]
    cmp x1, #6
    b.eq .Lshow_float
    cmp x1, #2
    b.eq .Lshow_nil
    cmp x1, #1
    b.eq .Lshow_list
    cmp x1, #3
    b.eq .Lshow_tuple
    cmp x1, #5
    b.eq .Lshow_adt
    ldp x29, x30, [sp], #32
    ret
.Lshow_tuple:
    bl _rail_show_tuple
    ldp x29, x30, [sp], #32
    ret
.Lshow_adt:
    bl _rail_show_adt
    ldp x29, x30, [sp], #32
    ret
.Lshow_nil:
    mov x0, #4
    bl _rail_chained_malloc
    mov w1, #91
    strb w1, [x0]
    mov w1, #93
    strb w1, [x0, #1]
    mov w1, #0
    strb w1, [x0, #2]
    ldp x29, x30, [sp], #32
    ret
.Lshow_list:
    bl _rail_show_list
    ldp x29, x30, [sp], #32
    ret
.Lshow_float:
    ldr d0, [x0, #8]
    str d0, [x29, #24]
    mov x0, #32
    bl _rail_chained_malloc
    str x0, [x29, #16]
    ldr d0, [x29, #24]
    str d0, [sp, #-16]!
    ldr x0, [x29, #16]
    mov x1, #32
    adrp x2, _fmt_gbare@PAGE
    add x2, x2, _fmt_gbare@PAGEOFF
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

_rail_show_list:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, #4
    bl _rail_chained_malloc
    mov w1, #91
    strb w1, [x0]
    mov w1, #0
    strb w1, [x0, #1]
    str x0, [x29, #24]
    mov x0, #4
    bl _rail_chained_malloc
    mov w1, #44
    strb w1, [x0]
    mov w1, #32
    strb w1, [x0, #1]
    mov w1, #0
    strb w1, [x0, #2]
    str x0, [x29, #32]
    mov x0, #4
    bl _rail_chained_malloc
    mov w1, #93
    strb w1, [x0]
    mov w1, #0
    strb w1, [x0, #1]
    str x0, [x29, #40]
    mov x0, #1
    str x0, [x29, #48]
.Lshowl_loop:
    ldr x0, [x29, #16]
    tst x0, #1
    b.ne .Lshowl_done
    ldr x1, [x0]
    cmp x1, #2
    b.eq .Lshowl_done
    cmp x1, #1
    b.ne .Lshowl_done
    ldr x0, [x29, #48]
    cbnz x0, .Lshowl_skip_sep
    ldr x0, [x29, #24]
    ldr x1, [x29, #32]
    bl _rail_str_append
    str x0, [x29, #24]
.Lshowl_skip_sep:
    str xzr, [x29, #48]
    ldr x0, [x29, #16]
    ldr x0, [x0, #8]
    bl _rail_show
    mov x1, x0
    ldr x0, [x29, #24]
    bl _rail_str_append
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    ldr x0, [x0, #16]
    str x0, [x29, #16]
    b .Lshowl_loop
.Lshowl_done:
    ldr x0, [x29, #24]
    ldr x1, [x29, #40]
    bl _rail_str_append
    ldp x29, x30, [sp], #64
    ret

// ARM64 _rail_str_append: O(n+m) via strlen+memcpy, mirroring the x86
// fix at c30ff5f. The previous strcpy+strcat sequence was O(n^2) on
// chained `s = s + chunk` accumulators because strcat re-scans the
// destination to find NUL on every call. Now both copies use memcpy
// with pre-computed lengths and we plant the NUL explicitly.
// Frame: #16=str1_uw, #24=str2_uw, #32=len1, #40=buf, #48=len2.
//@ let rstrapp
_rail_str_append:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    bl _str_unwrap
    str x0, [x29, #16]
    ldr x0, [x29, #24]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _strlen
    str x0, [x29, #32]
    ldr x0, [x29, #24]
    bl _strlen
    str x0, [x29, #48]
    ldr x1, [x29, #32]
    add x0, x0, x1
    add x0, x0, #1
    bl _rail_chained_malloc
    str x0, [x29, #40]
    ldr x1, [x29, #16]
    ldr x2, [x29, #32]
    bl _memcpy
    ldr x0, [x29, #40]
    ldr x1, [x29, #32]
    add x0, x0, x1
    ldr x1, [x29, #24]
    ldr x2, [x29, #48]
    bl _memcpy
    ldr x0, [x29, #40]
    ldr x1, [x29, #32]
    ldr x2, [x29, #48]
    add x1, x1, x2
    add x0, x0, x1
    strb wzr, [x0]
    ldr x0, [x29, #40]
    ldp x29, x30, [sp], #64
    ret

// _rail_fval / _rail_fval1: a GENERIC value (x0 / x1) read as a double
// (d0 / d1). Tagged int: converted. Heap float box (tag 6): loaded. Anything
// else is taken as raw binary64 bits, the convention statically-typed float
// code uses; a heap pointer is told from raw bits by shape (bits below 2^47
// and above 4095 are pointers, so a positive subnormal in that range would be
// misread; every normal double, every negative one and 0.0 are outside it).
// Since 2026-09-11 every generic runtime routine and every generic-to-float
// codegen site reads through these; the old `.L*_mixed_*` arms read the
// untagged operand as raw bits in one routine and as a box in the next
// (findings F-5000-2, known/mixed_int_from_fn).
//@ let rfval
_rail_fval:
    tst x0, #1
    b.ne .Lfv_int
    lsr x2, x0, #47
    cbnz x2, .Lfv_raw
    cmp x0, #4095
    b.ls .Lfv_raw
    ldr x2, [x0]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.ne .Lfv_raw
    ldr d0, [x0, #8]
    ret
.Lfv_raw:
    fmov d0, x0
    ret
.Lfv_int:
    asr x2, x0, #1
    scvtf d0, x2
    ret

_rail_fval1:
    tst x1, #1
    b.ne .Lfv1_int
    lsr x2, x1, #47
    cbnz x2, .Lfv1_raw
    cmp x1, #4095
    b.ls .Lfv1_raw
    ldr x2, [x1]
    and x2, x2, #0x7fffffffffffffff
    cmp x2, #6
    b.ne .Lfv1_raw
    ldr d1, [x1, #8]
    ret
.Lfv1_raw:
    fmov d1, x1
    ret
.Lfv1_int:
    asr x2, x1, #1
    scvtf d1, x2
    ret

// show for tuples ("(a, b)") and constructed values ("Name f1 f2", a field that is itself a
// constructed value with fields in parentheses), by the tuple length and the constructor
// tables; show of a value the code generator knows is a bool prints true or false. Until
// 2026-09-23 a tuple or a constructed value printed its header bytes (nothing visible).
//@ let rshow2
_rail_show_tuple:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, #4
    bl _rail_chained_malloc
    mov w1, #40
    strb w1, [x0]
    mov w1, #0
    strb w1, [x0, #1]
    str x0, [x29, #24]
    str xzr, [x29, #32]
.Lsht_loop:
    ldr x2, [x29, #32]
    ldr x0, [x29, #16]
    ldr x1, [x0, #8]
    cmp x2, x1
    b.hs .Lsht_done
    cbz x2, .Lsht_first
    ldr x0, [x29, #24]
    mov x1, #44
    bl _rail_sapp_ch
    mov x1, #32
    bl _rail_sapp_ch
    str x0, [x29, #24]
.Lsht_first:
    ldr x2, [x29, #32]
    add x2, x2, #2
    ldr x0, [x29, #16]
    ldr x0, [x0, x2, lsl #3]
    bl _rail_show
    mov x1, x0
    ldr x0, [x29, #24]
    bl _rail_str_append
    str x0, [x29, #24]
    ldr x2, [x29, #32]
    add x2, x2, #1
    str x2, [x29, #32]
    b .Lsht_loop
.Lsht_done:
    ldr x0, [x29, #24]
    mov x1, #41
    bl _rail_sapp_ch
    ldp x29, x30, [sp], #48
    ret

_rail_show_adt:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    ldr x1, [x0, #8]
    adrp x2, _rail_ctor_count@PAGE
    ldr x2, [x2, _rail_ctor_count@PAGEOFF]
    cmp x1, x2
    b.hs .Lsha_unknown
    adrp x2, _rail_ctor_arity@PAGE
    add x2, x2, _rail_ctor_arity@PAGEOFF
    ldr x3, [x2, x1, lsl #3]
    str x3, [x29, #40]
    adrp x2, _rail_ctor_name@PAGE
    add x2, x2, _rail_ctor_name@PAGEOFF
    ldr x0, [x2, x1, lsl #3]
    str x0, [x29, #24]
    str xzr, [x29, #32]
.Lsha_loop:
    ldr x2, [x29, #32]
    ldr x3, [x29, #40]
    cmp x2, x3
    b.hs .Lsha_done
    ldr x0, [x29, #24]
    mov x1, #32
    bl _rail_sapp_ch
    str x0, [x29, #24]
    ldr x2, [x29, #32]
    add x2, x2, #2
    ldr x0, [x29, #16]
    ldr x0, [x0, x2, lsl #3]
    str x0, [x29, #48]
    bl _rail_show
    str x0, [x29, #56]
    ldr x0, [x29, #48]
    bl _rail_show_needs_paren
    cbz x0, .Lsha_plain
    ldr x0, [x29, #24]
    mov x1, #40
    bl _rail_sapp_ch
    ldr x1, [x29, #56]
    bl _rail_str_append
    mov x1, #41
    bl _rail_sapp_ch
    str x0, [x29, #24]
    b .Lsha_next
.Lsha_plain:
    ldr x0, [x29, #24]
    ldr x1, [x29, #56]
    bl _rail_str_append
    str x0, [x29, #24]
.Lsha_next:
    ldr x2, [x29, #32]
    add x2, x2, #1
    str x2, [x29, #32]
    b .Lsha_loop
.Lsha_done:
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #64
    ret
.Lsha_unknown:
    mov x0, #4
    bl _rail_chained_malloc
    mov w1, #63
    strb w1, [x0]
    mov w1, #0
    strb w1, [x0, #1]
    ldp x29, x30, [sp], #64
    ret

_rail_show_needs_paren:
    tst x0, #1
    b.ne .Lsnp_no
    cbz x0, .Lsnp_no
    lsr x1, x0, #47
    cbnz x1, .Lsnp_no
    cmp x0, #4095
    b.ls .Lsnp_no
    ldr x1, [x0]
    cmp x1, #5
    b.ne .Lsnp_no
    ldr x1, [x0, #8]
    adrp x2, _rail_ctor_count@PAGE
    ldr x2, [x2, _rail_ctor_count@PAGEOFF]
    cmp x1, x2
    b.hs .Lsnp_no
    adrp x2, _rail_ctor_arity@PAGE
    add x2, x2, _rail_ctor_arity@PAGEOFF
    ldr x1, [x2, x1, lsl #3]
    cbz x1, .Lsnp_no
    mov x0, #1
    ret
.Lsnp_no:
    mov x0, #0
    ret

_rail_sapp_ch:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    mov x0, #4
    bl _rail_chained_malloc
    ldr x1, [x29, #24]
    strb w1, [x0]
    mov w1, #0
    strb w1, [x0, #1]
    mov x1, x0
    ldr x0, [x29, #16]
    bl _rail_str_append
    ldp x29, x30, [sp], #32
    ret

_rail_show_bool:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    mov x0, #8
    bl _rail_chained_malloc
    ldr x1, [x29, #16]
    cmp x1, #3
    b.eq .Lshb_true
    mov w1, #102
    strb w1, [x0]
    mov w1, #97
    strb w1, [x0, #1]
    mov w1, #108
    strb w1, [x0, #2]
    mov w1, #115
    strb w1, [x0, #3]
    mov w1, #101
    strb w1, [x0, #4]
    mov w1, #0
    strb w1, [x0, #5]
    b .Lshb_wrap
.Lshb_true:
    mov w1, #116
    strb w1, [x0]
    mov w1, #114
    strb w1, [x0, #1]
    mov w1, #117
    strb w1, [x0, #2]
    mov w1, #101
    strb w1, [x0, #3]
    mov w1, #0
    strb w1, [x0, #4]
.Lshb_wrap:
    bl _rail_wrap_str
    ldp x29, x30, [sp], #32
    ret

//@ cat req, rne, reqh, radd, rprint, rshow, rshow2, rstrapp, rfval
