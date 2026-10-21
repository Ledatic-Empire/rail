// rt_syscall: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// setjmp/longjmp + malloc/free: final libc eliminations
// Batch 1: string functions (inline ARM64 loops)
//@ let nstrlen
_strlen:
    mov x1, x0
    mov x0, #0
.Lsl_loop:
    ldrb w2, [x1, x0]
    cbz w2, .Lsl_done
    add x0, x0, #1
    b .Lsl_loop
.Lsl_done:
    ret

//@ let nstrcmp
_strcmp:
    mov x2, #0
.Lsc_loop:
    ldrb w3, [x0, x2]
    ldrb w4, [x1, x2]
    cmp w3, w4
    b.ne .Lsc_diff
    cbz w3, .Lsc_eq
    add x2, x2, #1
    b .Lsc_loop
.Lsc_diff:
    sub x0, x3, x4
    ret
.Lsc_eq:
    mov x0, #0
    ret

//@ let nstrcpy
_strcpy:
    mov x2, x0
    mov x3, #0
.Lscp_loop:
    ldrb w4, [x1, x3]
    strb w4, [x0, x3]
    cbz w4, .Lscp_done
    add x3, x3, #1
    b .Lscp_loop
.Lscp_done:
    mov x0, x2
    ret

//@ let nstrcat
_strcat:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    bl _strlen
    ldr x1, [x29, #24]
    ldr x2, [x29, #16]
    add x0, x2, x0
    bl _strcpy
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #32
    ret

//@ let natoi
_atoi:
    mov x1, #0
    mov x2, #0
    ldrb w3, [x0]
    cmp w3, #45
    b.ne .Latoi_loop
    mov x2, #1
    add x0, x0, #1
.Latoi_loop:
    ldrb w3, [x0], #1
    cbz w3, .Latoi_done
    cmp w3, #48
    b.lt .Latoi_done
    cmp w3, #57
    b.gt .Latoi_done
    sub w3, w3, #48
    mov x4, #10
    mul x1, x1, x4
    add x1, x1, x3
    b .Latoi_loop
.Latoi_done:
    cbz x2, .Latoi_pos
    neg x1, x1
.Latoi_pos:
    mov x0, x1
    ret

//@ let nstrstr
_strstr:
    ldrb w2, [x1]
    cbz w2, .Lstrstr_match
.Lstrstr_outer:
    ldrb w2, [x0]
    cbz w2, .Lstrstr_notfound
    mov x3, x0
    mov x4, x1
.Lstrstr_inner:
    ldrb w5, [x4]
    cbz w5, .Lstrstr_match
    ldrb w6, [x3]
    cbz w6, .Lstrstr_advance
    cmp w5, w6
    b.ne .Lstrstr_advance
    add x3, x3, #1
    add x4, x4, #1
    b .Lstrstr_inner
.Lstrstr_advance:
    add x0, x0, #1
    b .Lstrstr_outer
.Lstrstr_match:
    ret
.Lstrstr_notfound:
    mov x0, #0
    ret

// Batch 4+5: file I/O (Darwin syscalls)
// _fopen unwraps both args via _str_unwrap before the open(2) syscall
// so user-FFI `foreign fopen path mode -> int` works whether the path
// is a literal (raw C-string) or a wrapped Rail string (e.g., from
// argv via _rail_args). Without this, wrapped strings would be passed
// with the ptr at the 16-byte header, so open() reads `\x09\0` (the
// header tag value) as the path. _rail_read_file (the read_file
// builtin) already unwraps before calling _fopen, this brings the
// user-FFI path to parity. Idempotent: _str_unwrap on an already-
// unwrapped C-string returns it unchanged.
// A failed open returns 0. Darwin reports a syscall error with the carry
// flag set and a POSITIVE errno in x0 (the branches to .Lfop_done leave the
// flags alone); until 2026-10-06 this tested x0 < 0, the Linux convention,
// so a missing file came back as 2 (ENOENT), which is fd 2: every fp == 0
// guard missed it, read_file read stderr, and its fclose closed stderr.
//@ let nfopen
_fopen:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x1, [x29, #16]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    mov x1, x0
    ldr x0, [x29, #24]
    ldrb w2, [x1]
    cmp w2, #119
    b.eq .Lfop_w
    cmp w2, #97
    b.eq .Lfop_a
    mov x1, #0
    mov x2, #0
    movz x16, #5
    movk x16, #0x200, lsl #16
    svc #0x80
    b .Lfop_done
.Lfop_w:
    mov x1, #0x601
    mov x2, #0x1A4
    movz x16, #5
    movk x16, #0x200, lsl #16
    svc #0x80
    b .Lfop_done
.Lfop_a:
    mov x1, #0x209
    mov x2, #0x1A4
    movz x16, #5
    movk x16, #0x200, lsl #16
    svc #0x80
.Lfop_done:
    b.cc .Lfop_ok
    mov x0, #0
.Lfop_ok:
    ldp x29, x30, [sp], #32
    ret

//@ let nfread
_fread:
    mul x2, x1, x2
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]
    str x2, [x29, #24]
    str x3, [x29, #32]
    str xzr, [x29, #40]
.Lfrd_loop:
    ldr x2, [x29, #24]
    cbz x2, .Lfrd_done
    mov x4, #0x40000000
    cmp x2, x4
    csel x2, x2, x4, lo
    ldr x0, [x29, #32]
    ldr x1, [x29, #16]
    movz x16, #3
    movk x16, #0x200, lsl #16
    svc #0x80
    b.cs .Lfrd_done
    cmp x0, #1
    b.lt .Lfrd_done
    ldr x1, [x29, #16]
    add x1, x1, x0
    str x1, [x29, #16]
    ldr x2, [x29, #24]
    sub x2, x2, x0
    str x2, [x29, #24]
    ldr x3, [x29, #40]
    add x3, x3, x0
    str x3, [x29, #40]
    b .Lfrd_loop
.Lfrd_done:
    ldr x0, [x29, #40]
    ldp x29, x30, [sp], #48
    ret

//@ let nfwrite
_fwrite:
    mul x2, x1, x2
    mov x1, x0
    mov x0, x3
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

//@ let nfclose
_fclose:
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

//@ let nfseek
_fseek:
    movz x16, #199
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #0
    ret

//@ let nftell
_ftell:
    mov x1, #0
    mov x2, #1
    movz x16, #199
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

//@ let nread
_read:
    movz x16, #3
    movk x16, #0x200, lsl #16
    svc #0x80
    ret

//@ let nfflush
_fflush:
    ret

// setjmp/longjmp + malloc/free
//@ let nsetjmp
_setjmp:
    stp x19, x20, [x0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x1, sp
    str x1, [x0, #96]
    stp d8, d9, [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]
    mov x0, #0
    ret

//@ let nlongjmp
_longjmp:
    ldp x19, x20, [x0]
    ldp x21, x22, [x0, #16]
    ldp x23, x24, [x0, #32]
    ldp x25, x26, [x0, #48]
    ldp x27, x28, [x0, #64]
    ldp x29, x30, [x0, #80]
    ldr x2, [x0, #96]
    mov sp, x2
    ldp d8, d9, [x0, #104]
    ldp d10, d11, [x0, #120]
    ldp d12, d13, [x0, #136]
    ldp d14, d15, [x0, #152]
    mov x0, x1
    cbnz x0, .Llj_done
    mov x0, #1
.Llj_done:
    ret

//@ let nmalloc
_malloc:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    add x0, x0, #15
    and x0, x0, #-16
    str x0, [x29, #16]
    cmp x0, #65536
    b.hi .Lmal_large
    adrp x1, _rail_malloc_ptr@PAGE
    add x1, x1, _rail_malloc_ptr@PAGEOFF
    ldr x2, [x1]
    cbz x2, .Lmal_newpage
    ldr x3, [x29, #16]
    add x4, x2, x3
    adrp x5, _rail_malloc_end@PAGE
    ldr x5, [x5, _rail_malloc_end@PAGEOFF]
    cmp x4, x5
    b.hi .Lmal_newpage
    str x4, [x1]
    mov x0, x2
    ldp x29, x30, [sp], #32
    ret
.Lmal_newpage:
    mov x0, #0
    mov x1, #0x400000
    mov x2, #3
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    movz x16, #197
    movk x16, #0x200, lsl #16
    svc #0x80
    b.cs .Lmal_fail
    adrp x1, _rail_malloc_ptr@PAGE
    add x1, x1, _rail_malloc_ptr@PAGEOFF
    ldr x2, [x29, #16]
    add x3, x0, x2
    str x3, [x1]
    add x5, x0, #0x400000
    adrp x6, _rail_malloc_end@PAGE
    add x6, x6, _rail_malloc_end@PAGEOFF
    str x5, [x6]
    ldp x29, x30, [sp], #32
    ret
.Lmal_large:
    ldr x1, [x29, #16]
    mov x0, #0
    mov x2, #3
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    movz x16, #197
    movk x16, #0x200, lsl #16
    svc #0x80
    b.cs .Lmal_fail
    adrp x1, _rail_mmap_large_count@PAGE
    add x1, x1, _rail_mmap_large_count@PAGEOFF
    ldr x2, [x1]
    add x2, x2, #1
    str x2, [x1]
    ldp x29, x30, [sp], #32
    ret
.Lmal_fail:
    mov x0, #0
    ldp x29, x30, [sp], #32
    ret

//@ let nfree
_free:
    ret

//@ cat nstrlen, nstrcmp, nstrcpy, nstrcat, natoi, nstrstr, nfopen, nfread, nfwrite, nfclose, nfseek, nftell, nread, nfflush, nsetjmp, nlongjmp, nmalloc, nfree
