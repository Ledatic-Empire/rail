// rt_string: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// str_find needle haystack → tagged int index (-1 if not found)
//@ let sfind
_rail_str_find:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x1, [x29, #16]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    str x0, [x29, #16]
    ldr x1, [x29, #24]
    bl _strstr
    cbz x0, .Lsf_notfound
    ldr x1, [x29, #16]
    sub x0, x0, x1
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret
.Lsf_notfound:
    mov x0, #-1
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret

// str_contains needle haystack → tagged bool (3=true, 1=false)
//@ let scont
_rail_str_contains:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x1, [x29, #16]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _str_unwrap
    ldr x1, [x29, #24]
    bl _strstr
    cmp x0, #0
    cset x0, ne
    lsl x0, x0, #1
    orr x0, x0, #1
    ldp x29, x30, [sp], #32
    ret

// str_sub string start len → new string
//@ let ssub
_rail_str_sub:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x1, [x29, #24]
    str x2, [x29, #32]
    bl _str_unwrap
    str x0, [x29, #16]
    ldr x1, [x29, #24]
    asr x1, x1, #1
    str x1, [x29, #24]
    ldr x2, [x29, #32]
    asr x2, x2, #1
    str x2, [x29, #32]
    add x0, x2, #1
    bl _malloc
    str x0, [x29, #40]
    ldr x1, [x29, #16]
    ldr x2, [x29, #24]
    add x1, x1, x2
    ldr x2, [x29, #32]
    mov x3, x2
.Lss_cp:
    cbz x3, .Lss_done
    ldrb w4, [x1], #1
    strb w4, [x0], #1
    sub x3, x3, #1
    b .Lss_cp
.Lss_done:
    mov w4, #0
    strb w4, [x0]
    ldr x0, [x29, #40]
    bl _rail_wrap_str
    str x0, [x29, #16]
    ldr x0, [x29, #40]
    bl _free
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #48
    ret

// str_replace old new string → new string (replaces all occurrences)
// Uses strstr loop with proper frame management
//@ let srepl
_rail_str_replace:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    str x1, [x29, #24]
    str x2, [x29, #32]
    bl _str_unwrap
    str x0, [x29, #16]
    ldr x0, [x29, #24]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #32]
    bl _str_unwrap
    str x0, [x29, #32]
    bl _strlen
    str x0, [x29, #40]
    ldr x0, [x29, #16]
    bl _strlen
    str x0, [x29, #48]
    ldr x0, [x29, #24]
    bl _strlen
    str x0, [x29, #56]
    ldr x0, [x29, #40]
    lsl x0, x0, #2
    add x0, x0, #64
    bl _malloc
    str x0, [x29, #64]
    str xzr, [x29, #72]
    ldr x0, [x29, #32]
    str x0, [x29, #80]
.Lsr_loop:
    ldr x0, [x29, #80]
    ldr x1, [x29, #16]
    bl _strstr
    cbz x0, .Lsr_rest
    str x0, [x29, #88]
    ldr x1, [x29, #80]
    sub x2, x0, x1
    ldr x3, [x29, #64]
    ldr x4, [x29, #72]
    add x5, x3, x4
    mov x6, x2
.Lsr_cp1:
    cbz x6, .Lsr_cp1d
    ldrb w7, [x1], #1
    strb w7, [x5], #1
    sub x6, x6, #1
    b .Lsr_cp1
.Lsr_cp1d:
    ldr x4, [x29, #72]
    add x4, x4, x2
    ldr x1, [x29, #24]
    ldr x6, [x29, #56]
.Lsr_cp2:
    cbz x6, .Lsr_cp2d
    ldrb w7, [x1], #1
    strb w7, [x5], #1
    sub x6, x6, #1
    b .Lsr_cp2
.Lsr_cp2d:
    ldr x6, [x29, #56]
    add x4, x4, x6
    str x4, [x29, #72]
    ldr x0, [x29, #88]
    ldr x1, [x29, #48]
    add x0, x0, x1
    str x0, [x29, #80]
    b .Lsr_loop
.Lsr_rest:
    ldr x1, [x29, #80]
    ldr x3, [x29, #64]
    ldr x4, [x29, #72]
    add x5, x3, x4
.Lsr_cp3:
    ldrb w7, [x1], #1
    strb w7, [x5], #1
    cbnz w7, .Lsr_cp3
    ldr x0, [x29, #64]
    bl _rail_wrap_str
    str x0, [x29, #16]
    ldr x0, [x29, #64]
    bl _free
    ldr x0, [x29, #16]
    ldp x29, x30, [sp], #96
    ret

// str_split delim string → list (multi-char delimiter)
//@ let ssplit
_rail_str_split:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    str x0, [x29, #64]
    str x1, [x29, #72]
    str x1, [x29, #24]
    bl _str_unwrap
    str x0, [x29, #16]
    ldr x0, [x29, #24]
    bl _str_unwrap
    str x0, [x29, #24]
    ldr x0, [x29, #16]
    bl _strlen
    str x0, [x29, #32]
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    str x0, [x29, #40]
    ldr x0, [x29, #24]
    str x0, [x29, #48]
.Lssp_loop:
    ldr x0, [x29, #48]
    ldr x1, [x29, #16]
    bl _strstr
    cbz x0, .Lssp_last
    str x0, [x29, #56]
    ldr x1, [x29, #48]
    sub x2, x0, x1
    add x0, x2, #1
    bl _rail_chained_malloc
    str x0, [sp, #-16]!
    ldr x1, [x29, #48]
    ldr x3, [x29, #56]
    sub x2, x3, x1
    mov x4, x2
.Lssp_cp:
    cbz x4, .Lssp_cpd
    ldrb w5, [x1], #1
    strb w5, [x0], #1
    sub x4, x4, #1
    b .Lssp_cp
.Lssp_cpd:
    mov w5, #0
    strb w5, [x0]
    ldr x0, [sp], #16
    bl _rail_wrap_str
    ldr x1, [x29, #40]
    bl _rail_cons
    str x0, [x29, #40]
    ldr x0, [x29, #56]
    ldr x1, [x29, #32]
    add x0, x0, x1
    str x0, [x29, #48]
    b .Lssp_loop
.Lssp_last:
    ldr x0, [x29, #48]
    bl _strlen
    add x0, x0, #1
    bl _rail_chained_malloc
    str x0, [sp, #-16]!
    ldr x1, [x29, #48]
    bl _strcpy
    ldr x0, [sp], #16
    bl _rail_wrap_str
    ldr x1, [x29, #40]
    bl _rail_cons
    str x0, [x29, #40]
    ldr x0, [x29, #40]
    bl _rail_reverse
    ldp x29, x30, [sp], #80
    ret

// read_line → string (reads one line from stdin)
//
// Restored 2026-04-08 via raw libc `read` on fd 0. Avoids the macOS-only
// `___stdinp@GOTPAGE` indirection that broke the Linux asm transform on
// 2026-04-07. `read` is in libSystem (macOS) and libc (Linux) under the
// same name, so the asm-transform underscore strip handles both targets.
// Reads one byte at a time until newline, EOF, or 1023 bytes. Result is a
// malloc'd null-terminated string with the trailing newline stripped.
//@ let readline
_rail_read_line:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [x29, #16]
    str x20, [x29, #24]
    mov x0, #1024
    bl _rail_chained_malloc
    mov x19, x0
    mov x20, #0
.Lrl_loop:
    cmp x20, #1023
    b.ge .Lrl_done
    mov x0, #0
    add x1, x19, x20
    mov x2, #1
    bl _read
    cmp x0, #1
    b.lt .Lrl_done
    ldrb w0, [x19, x20]
    cmp w0, #10
    b.eq .Lrl_done
    add x20, x20, #1
    b .Lrl_loop
.Lrl_done:
    mov w0, #0
    strb w0, [x19, x20]
    mov x0, x19
    bl _rail_wrap_str
    ldr x19, [x29, #16]
    ldr x20, [x29, #24]
    ldp x29, x30, [sp], #32
    ret

//@ cat sfind, scont, ssub, srepl, ssplit, readline
