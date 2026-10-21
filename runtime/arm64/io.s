// rt_io: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ let rwritefile
_rail_write_file:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x1, [x29, #16]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    str x0, [x29, #16]
    ldr x0, [x29, #24]
    adrp x1, _mode_w@PAGE
    add x1, x1, _mode_w@PAGEOFF
    bl _fopen
    str x0, [x29, #32]
    ldr x0, [x29, #16]
    bl _strlen
    ldr x3, [x29, #32]
    mov x2, x0
    ldr x0, [x29, #16]
    mov x1, #1
    bl _fwrite
    ldr x0, [x29, #32]
    bl _fclose
    mov x0, #1
    ldp x29, x30, [sp], #48
    ret

//@ let rshell
_rail_shell:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    bl _str_unwrap
    str x0, [x29, #16]
    movz x16, #42
    movk x16, #0x200, lsl #16
    svc #0x80
    str w0, [x29, #24]
    str w1, [x29, #28]
    movz x16, #2
    movk x16, #0x200, lsl #16
    svc #0x80
    cbz x1, .Lsh_parent
    ldr w0, [x29, #28]
    mov x1, #1
    movz x16, #90
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr w0, [x29, #24]
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr w0, [x29, #28]
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    adr x0, .Lsh_binsh
    str x0, [x29, #48]
    adr x0, .Lsh_cflag
    str x0, [x29, #56]
    ldr x0, [x29, #16]
    str x0, [x29, #64]
    str xzr, [x29, #72]
    adr x0, .Lsh_binsh
    add x1, x29, #48
    adrp x2, _rail_envp@PAGE
    ldr x2, [x2, _rail_envp@PAGEOFF]
    movz x16, #59
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #1
    movz x16, #1
    movk x16, #0x200, lsl #16
    svc #0x80
.Lsh_binsh:
    .asciz "/bin/sh"
    .p2align 2
.Lsh_cflag:
    .asciz "-c"
    .p2align 2
.Lsh_parent:
    str x0, [x29, #32]
    ldr w0, [x29, #28]
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #65536
    bl _malloc
    str x0, [x29, #40]
    str xzr, [x29, #48]
.Lsh_read:
    ldr w0, [x29, #24]
    ldr x1, [x29, #40]
    ldr x2, [x29, #48]
    add x1, x1, x2
    mov x2, #4096
    movz x16, #3
    movk x16, #0x200, lsl #16
    svc #0x80
    cmp x0, #0
    b.le .Lsh_done
    ldr x1, [x29, #48]
    add x1, x1, x0
    str x1, [x29, #48]
    b .Lsh_read
.Lsh_done:
    ldr w0, [x29, #24]
    movz x16, #6
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #-1
    add x1, x29, #56
    mov x2, #0
    mov x3, #0
    movz x16, #7
    movk x16, #0x200, lsl #16
    svc #0x80
    ldr x0, [x29, #40]
    ldr x1, [x29, #48]
    mov w2, #0
    strb w2, [x0, x1]
    ldr x0, [x29, #40]
    bl _rail_wrap_str
    str x0, [x29, #56]
    ldr x0, [x29, #40]
    bl _free
    ldr x0, [x29, #56]
    ldp x29, x30, [sp], #96
    ret

//@ let rreadfile
_rail_read_file:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    bl _str_unwrap
    adrp x1, _mode_r@PAGE
    add x1, x1, _mode_r@PAGEOFF
    bl _fopen
    cbz x0, .Lrf_empty
    str x0, [x29, #16]
    mov x1, #0
    mov x2, #2
    bl _fseek
    ldr x0, [x29, #16]
    bl _ftell
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    mov x1, #0
    mov x2, #0
    bl _fseek
    ldr x0, [x29, #24]
    add x0, x0, #1
    bl _malloc
    str x0, [x29, #32]
    mov x1, #1
    ldr x2, [x29, #24]
    ldr x3, [x29, #16]
    bl _fread
    ldr x0, [x29, #32]
    ldr x1, [x29, #24]
    mov w2, #0
    strb w2, [x0, x1]
    ldr x0, [x29, #16]
    bl _fclose
    ldr x0, [x29, #32]
    bl _rail_wrap_str
    str x0, [x29, #16]
    ldr x0, [x29, #32]
    bl _free
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #48
    ret
.Lrf_empty:
    adrp x0, _rail_empty_str@PAGE
    add x0, x0, _rail_empty_str@PAGEOFF
    bl _rail_wrap_str
    ldp x29, x30, [sp], #48
    ret

// read_file_bytes: whole-file binary reader. Mirrors _rail_read_file's
// proven fopen/ftell/fread path but returns the RAW malloc'd buffer WITHOUT
// the strlen-based _rail_wrap_str (which truncates at the first 0x00). The
// result is a raw byte buffer indexed directly by byte_at (same convention as
// a cat-built C string), so interior nulls are preserved -- the safetensors
// 8-byte LE header length (0x00 at byte 1) is now readable. On open failure
// returns a 1-byte zero buffer so byte_at never dereferences null.
//@ let rreadfilebytes
_rail_read_file_bytes:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    bl _str_unwrap
    adrp x1, _mode_r@PAGE
    add x1, x1, _mode_r@PAGEOFF
    bl _fopen
    cbz x0, .Lrfb_empty
    str x0, [x29, #16]
    mov x1, #0
    mov x2, #2
    bl _fseek
    ldr x0, [x29, #16]
    bl _ftell
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    mov x1, #0
    mov x2, #0
    bl _fseek
    ldr x0, [x29, #24]
    add x0, x0, #1
    bl _malloc
    str x0, [x29, #32]
    mov x1, #1
    ldr x2, [x29, #24]
    ldr x3, [x29, #16]
    bl _fread
    ldr x0, [x29, #32]
    ldr x1, [x29, #24]
    mov w2, #0
    strb w2, [x0, x1]
    ldr x0, [x29, #16]
    bl _fclose
    ldr x0, [x29, #32]
    ldp x29, x30, [sp], #48
    ret
.Lrfb_empty:
    mov x0, #1
    bl _malloc
    mov w1, #0
    strb w1, [x0]
    ldp x29, x30, [sp], #48
    ret

//@ cat rwritefile, rshell, rreadfile, rreadfilebytes
