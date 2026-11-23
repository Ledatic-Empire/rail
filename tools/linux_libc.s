// linux_libc.s — Syscall-based C library for Rail Linux ARM64 binaries
// No external dependencies. Pure syscalls + assembly string ops.
// Syscalls: write=64, read=63, openat=56, close=57, lseek=62, exit=93, mmap=222
// ---- String functions (pure assembly, all platforms) ----

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


// ---- Memory ----
// _malloc moved further down: it now bump-allocates from _rail_heap.
// _free remains a no-op (the bump arena does not support per-object free;
// reclamation only happens via _rail_gc, which dns-sink never triggers).

_free:
    ret

// ============ Rail runtime (Linux replacements) ============
// compile.rail emits Mac-ABI versions of the following _rail_* runtime
// stubs (svc #0x80 + Darwin syscall classes in x16). build_linux's
// strip awk drops them; these replacements use Linux conventions
// (svc #0, syscall # in x8). Keep both lists in sync — anything added
// here must also be added to the strip awk in build_linux.

// _rail_arena_init — Linux variant.
// Mach-O auto-invokes via __mod_init_func; on ELF we drop that stanza
// and call this explicitly from _start. Sets up the 1 GB _rail_heap
// region (BSS-allocated by build_linux's bss snippet) as the bump
// arena. No mmap needed since _rail_heap is statically reserved.
_rail_arena_init:
    adrp x0, _rail_heap
    add x0, x0, :lo12:_rail_heap
    adrp x1, _rail_heap_base
    add x1, x1, :lo12:_rail_heap_base
    str x0, [x1]
    adrp x1, _rail_heap_ptr
    add x1, x1, :lo12:_rail_heap_ptr
    str x0, [x1]
    mov x2, #0x40000000            // 1 GB
    add x2, x0, x2
    adrp x1, _rail_heap_end
    add x1, x1, :lo12:_rail_heap_end
    str x2, [x1]
    ret

// _rail_print — Linux variant.
// Same shape as the Mac version but with Linux syscall conventions
// (write = 64 in x8, svc #0). Handles tagged ints, heap floats, and
// heap strings. Always appends a trailing '\n'.
_rail_print:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    tst x0, #1
    b.eq .Lprnt_l_heap
    asr x0, x0, #1
    mov x1, #0
    cmp x0, #0
    b.ge .Lprnt_l_pos
    neg x0, x0
    mov x1, #1
.Lprnt_l_pos:
    str x1, [x29, #48]
    mov x2, #0
    mov x3, #10
    add x4, x29, #16
.Lprnt_l_div:
    udiv x5, x0, x3
    msub x6, x5, x3, x0
    add x6, x6, #48
    str x6, [sp, #-16]!
    add x2, x2, #1
    mov x0, x5
    cbnz x0, .Lprnt_l_div
    cbz x2, .Lprnt_l_zero
    mov x7, #0
    ldr x1, [x29, #48]
    cbz x1, .Lprnt_l_nosign
    mov w1, #45
    strb w1, [x4, x7]
    add x7, x7, #1
.Lprnt_l_nosign:
.Lprnt_l_rev:
    ldr x6, [sp], #16
    strb w6, [x4, x7]
    add x7, x7, #1
    sub x2, x2, #1
    cbnz x2, .Lprnt_l_rev
    mov w1, #10
    strb w1, [x4, x7]
    add x7, x7, #1
    mov x0, #1
    mov x1, x4
    mov x2, x7
    mov x8, #64
    svc #0
    b .Lprnt_l_done
.Lprnt_l_zero:
    mov w0, #48
    strb w0, [x4]
    mov w0, #10
    strb w0, [x4, #1]
    mov x0, #1
    mov x1, x4
    mov x2, #2
    mov x8, #64
    svc #0
    b .Lprnt_l_done
.Lprnt_l_heap:
    ldr x1, [x0]
    and x1, x1, #0x7fffffffffffffff
    cmp x1, #6
    b.eq .Lprnt_l_float
    bl _str_unwrap
    str x0, [x29, #16]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #16]
    mov x8, #64
    svc #0
    mov w0, #10
    strb w0, [x29, #24]
    mov x0, #1
    add x1, x29, #24
    mov x2, #1
    mov x8, #64
    svc #0
    b .Lprnt_l_done
.Lprnt_l_float:
    // Float printing path uses _snprintf (already in linux_libc.s).
    ldr d0, [x0, #8]
    str d0, [x29, #16]
    mov x0, #32
    bl _malloc
    str x0, [x29, #24]
    ldr d0, [x29, #16]
    str d0, [sp, #-16]!
    ldr x0, [x29, #24]
    mov x1, #32
    adrp x2, _fmt_gbare
    add x2, x2, :lo12:_fmt_gbare
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #24]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #24]
    mov x8, #64
    svc #0
    mov w0, #10
    strb w0, [x29, #32]
    mov x0, #1
    add x1, x29, #32
    mov x2, #1
    mov x8, #64
    svc #0
    ldr x0, [x29, #24]
    bl _free
.Lprnt_l_done:
    mov x0, #1
    ldp x29, x30, [sp], #64
    ret

// _rail_print_float — Linux variant. fmov-style branch is impossible
// from x0 because Mac _rail_print_float is called with d0 already set;
// the codegen for show_float / print_float dispatches via fmov d0, x0
// at the call site. Same convention here.
_rail_print_float:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str d0, [x29, #16]
    mov x0, #32
    bl _malloc
    str x0, [x29, #24]
    ldr d0, [x29, #16]
    str d0, [sp, #-16]!
    ldr x0, [x29, #24]
    mov x1, #32
    adrp x2, _fmt_gbare
    add x2, x2, :lo12:_fmt_gbare
    bl _snprintf
    add sp, sp, #16
    ldr x0, [x29, #24]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #24]
    mov x8, #64
    svc #0
    mov w0, #10
    strb w0, [x29, #32]
    mov x0, #1
    add x1, x29, #32
    mov x2, #1
    mov x8, #64
    svc #0
    ldr x0, [x29, #24]
    bl _free
    mov x0, #1
    ldp x29, x30, [sp], #48
    ret

// _rail_shell — Linux variant. Mac uses Darwin syscalls 42 (pipe),
// 2 (fork), 90 (dup2), 6 (close), 59 (execve), 1 (exit), 3 (read),
// 7 (waitpid). Linux equivalents: 59 (pipe2), 220 (clone), 24 (dup3),
// 57 (close), 221 (execve), 93 (exit), 63 (read), 260 (wait4).
//
// We use clone with SIGCHLD flag for fork-equivalence, dup3 with
// flags=0 for dup2-equivalence, pipe2 with flags=0 for pipe-equivalence.
// Linux ABI for clone: x0=flags, x1=child_stack (NULL=share parent's
// via copy-on-write). We pass SIGCHLD (0x11) so wait4 works.
_rail_shell:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    bl _str_unwrap
    str x0, [x29, #16]               // saved cmd string
    // pipe2(fds, 0)
    add x0, x29, #24
    mov x1, #0
    mov x8, #59                       // pipe2
    svc #0
    // ldr fds: x29#24 = read fd (32 bits), x29#28 = write fd
    // clone(SIGCHLD, NULL, ...)
    mov x0, #0x11                     // SIGCHLD
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, #220                      // clone
    svc #0
    cbz x0, .Lsh_l_child
    // parent: store pid
    str x0, [x29, #32]
    ldr w0, [x29, #28]                // close write end
    mov x8, #57                       // close
    svc #0
    // malloc 64K read buffer
    mov x0, #65536
    bl _malloc
    str x0, [x29, #40]
    str xzr, [x29, #48]
.Lsh_l_read:
    ldr w0, [x29, #24]
    ldr x1, [x29, #40]
    ldr x2, [x29, #48]
    add x1, x1, x2
    mov x2, #4096
    mov x8, #63                       // read
    svc #0
    cmp x0, #0
    b.le .Lsh_l_done
    ldr x1, [x29, #48]
    add x1, x1, x0
    str x1, [x29, #48]
    b .Lsh_l_read
.Lsh_l_done:
    ldr w0, [x29, #24]
    mov x8, #57                       // close
    svc #0
    // wait4(-1, &status, 0, NULL)
    mov x0, #-1
    add x1, x29, #56
    mov x2, #0
    mov x3, #0
    mov x8, #260                      // wait4
    svc #0
    // null-terminate buf
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
.Lsh_l_child:
    // child: dup3(write_fd, 1, 0)
    ldr w0, [x29, #28]
    mov x1, #1
    mov x2, #0
    mov x8, #24                       // dup3
    svc #0
    ldr w0, [x29, #24]
    mov x8, #57
    svc #0
    ldr w0, [x29, #28]
    mov x8, #57
    svc #0
    // execve("/bin/sh", argv, envp)
    adr x0, .Lsh_l_binsh
    str x0, [x29, #48]
    adr x0, .Lsh_l_cflag
    str x0, [x29, #56]
    ldr x0, [x29, #16]
    str x0, [x29, #64]
    str xzr, [x29, #72]
    adr x0, .Lsh_l_binsh
    add x1, x29, #48
    adrp x2, _rail_envp
    ldr x2, [x2, :lo12:_rail_envp]
    mov x8, #221                      // execve
    svc #0
    // exec failed; exit
    mov x0, #1
    mov x8, #93
    svc #0
.Lsh_l_binsh:
    .asciz "/bin/sh"
    .p2align 2
.Lsh_l_cflag:
    .asciz "-c"
    .p2align 2

// _rail_malloc_chain_drain — Linux variant.
// Walk the malloc chain back to _rail_chain_mark, releasing chunks.
// The Mac stub uses Darwin syscall #0x80 + class-0x02000000 munmap (73)
// in x16. On Linux, svc #0x80 with x8 holding stale data triggers
// arbitrary syscalls — the SEGV in pi_sign_server's serve_loop on the
// 2nd request was traced to that.
_rail_malloc_chain_drain:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x19, [x29, #16]
    str x20, [x29, #24]
    adrp x19, _rail_malloc_chain
    add x19, x19, :lo12:_rail_malloc_chain
    adrp x20, _rail_chain_mark
    add x20, x20, :lo12:_rail_chain_mark
.Lmdrn_l_loop:
    ldr x0, [x19]
    ldr x1, [x20]
    cmp x0, x1
    b.eq .Lmdrn_l_done
    cbz x0, .Lmdrn_l_done
    ldr x2, [x0]
    str x2, [x19]
    ldr x3, [x0, #8]
    cmp x3, #0x10000             // 65536
    b.ls .Lmdrn_l_small
    // large chunk: munmap. Linux munmap = syscall 215, x0=addr,
    // x1=length. The Mac version was svc #0x80 with x16=73|0x02000000.
    str x0, [x29, #32]
    str x3, [x29, #40]
    mov x1, x3
    mov x8, #215
    svc #0
    adrp x4, _rail_munmap_count
    add x4, x4, :lo12:_rail_munmap_count
    ldr x5, [x4]
    add x5, x5, #1
    str x5, [x4]
    b .Lmdrn_l_loop
.Lmdrn_l_small:
    sub x4, x3, #1
    clz x4, x4
    mov x5, #64
    sub x4, x5, x4
    sub x4, x4, #5
    adrp x5, _rail_small_fl
    add x5, x5, :lo12:_rail_small_fl
    add x5, x5, x4, lsl #3
    ldr x6, [x5]
    str x6, [x0]
    str x0, [x5]
    b .Lmdrn_l_loop
.Lmdrn_l_done:
    ldr x20, [x29, #24]
    ldr x19, [x29, #16]
    ldp x29, x30, [sp], #64
    ret

// _getenv(name) -> char* (the value, past '=') | 0
//
// Was a stub returning 0, on the reasoning that _rail_envp was not
// populated yet at arena-init time. Two things have changed. _start now
// computes envp from the initial stack and stores it BEFORE calling
// _rail_arena_init, so it is live throughout. And the stub was not only
// affecting the arena: `foreign getenv` is a Rail-level FFI, so every
// Linux program calling getenv got nothing back.
//
// Note the Linux _rail_arena_init does NOT consult this: it uses a
// statically reserved BSS heap of a fixed size, so RAIL_ARENA_MB still has
// no effect on Linux and would need an mmap path to gain one. Fixing that
// is a separate change; this fixes getenv.
//
// Walks the envp array comparing each "NAME=value" against name up to the
// '=', which is what makes "HOME" not match "HOMEBREW_PREFIX=...".
_getenv:
    mov x9, x0                    // x9 = name
    adrp x10, _rail_envp
    add x10, x10, :lo12:_rail_envp
    ldr x10, [x10]                // x10 = envp
    cbz x10, .Lge_none
.Lge_entry:
    ldr x11, [x10]                // x11 = envp[i]
    cbz x11, .Lge_none            // NULL terminator: not found
    mov x12, #0
.Lge_cmp:
    ldrb w13, [x9, x12]           // name[j]
    ldrb w14, [x11, x12]          // entry[j]
    cbz w13, .Lge_nameend         // name consumed
    cmp w13, w14
    b.ne .Lge_next
    add x12, x12, #1
    b .Lge_cmp
.Lge_nameend:
    cmp w14, #61                  // entry[j] must be '=' for a full match
    b.ne .Lge_next
    add x0, x11, x12
    add x0, x0, #1                // point past '='
    ret
.Lge_next:
    add x10, x10, #8
    b .Lge_entry
.Lge_none:
    mov x0, #0
    ret

// _strdup(s) -> char* — was missing entirely, so any Linux program using
// `foreign getenv` failed to LINK rather than misbehaving at runtime. The
// FFI string-return path calls it to copy a borrowed C string onto the
// Rail heap. NULL in gives an empty string out rather than faulting in
// _strlen, which is the shape getenv's not-found case needs.
_strdup:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    cbz x0, .Lsd_empty
    str x0, [x29, #16]
    bl _strlen
    add x0, x0, #1
    bl _malloc
    str x0, [x29, #24]
    ldr x1, [x29, #16]
    bl _strcpy
    ldr x0, [x29, #24]
    ldp x29, x30, [sp], #32
    ret
.Lsd_empty:
    mov x0, #1
    bl _malloc
    mov w1, #0
    strb w1, [x0]
    ldp x29, x30, [sp], #32
    ret

// read(fd, buf, count) — syscall 63
_read:
    mov x8, #63               // read
    svc #0
    ret

// write(fd, buf, count) — syscall 64
_write:
    mov x8, #64               // write
    svc #0
    ret

// ---- Printf: handles %ld\n, %s\n, raw strings ----

_printf:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    ldrb w1, [x0]
    cmp w1, #37          // '%'
    b.ne .Lpf_raw
    ldrb w1, [x0, #1]
    cmp w1, #108         // 'l' → %ld
    b.eq .Lpf_int
    cmp w1, #115         // 's' → %s
    b.eq .Lpf_str
    cmp w1, #103         // 'g' → %g (float stub)
    b.eq .Lpf_raw
    b .Lpf_raw

.Lpf_int:
    ldr x0, [x29, #48]   // value from caller stack
    // itoa into buffer at x29+16
    mov x1, #0            // negative flag
    cmp x0, #0
    b.ge .Lpfi_pos
    neg x0, x0
    mov x1, #1
.Lpfi_pos:
    str x1, [x29, #40]   // save neg flag
    mov x2, #0            // digit count
    mov x3, #10
    add x4, x29, #16     // buffer start
.Lpfi_div:
    udiv x5, x0, x3
    msub x6, x5, x3, x0
    add x6, x6, #48      // '0' + digit
    str x6, [sp, #-16]!  // push digit
    add x2, x2, #1
    mov x0, x5
    cbnz x0, .Lpfi_div
    // reverse digits into buffer
    mov x7, #0
    ldr x1, [x29, #40]
    cbz x1, .Lpfi_nosgn
    mov w1, #45           // '-'
    strb w1, [x4, x7]
    add x7, x7, #1
.Lpfi_nosgn:
.Lpfi_rev:
    ldr x6, [sp], #16
    strb w6, [x4, x7]
    add x7, x7, #1
    sub x2, x2, #1
    cbnz x2, .Lpfi_rev
    // write to stdout
    mov x2, x7
    mov x0, #1
    mov x1, x4
    mov x8, #64
    svc #0
    // newline
    mov w1, #10
    strb w1, [x29, #16]
    mov x0, #1
    add x1, x29, #16
    mov x2, #1
    mov x8, #64
    svc #0
    b .Lpf_done

.Lpf_str:
    ldr x0, [x29, #48]
    str x0, [x29, #16]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #16]
    mov x8, #64
    svc #0
    mov w1, #10
    strb w1, [x29, #24]
    mov x0, #1
    add x1, x29, #24
    mov x2, #1
    mov x8, #64
    svc #0
    b .Lpf_done

.Lpf_raw:
    str x0, [x29, #16]
    bl _strlen
    mov x2, x0
    mov x0, #1
    ldr x1, [x29, #16]
    mov x8, #64
    svc #0

.Lpf_done:
    ldp x29, x30, [sp], #48
    ret

// ---- snprintf: handles %ld → int-to-string ----

_snprintf:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    str x0, [x29, #16]   // buf
    str x1, [x29, #24]   // size
    ldrb w3, [x2, #1]
    cmp w3, #108          // 'l' → %ld
    b.eq .Lsnpf_int
    cmp w3, #46           // '.' → %.15g (float stub: write "0")
    b.eq .Lsnpf_float
    b .Lsnpf_done

.Lsnpf_int:
    ldr x0, [x29, #48]   // value from caller stack
    ldr x4, [x29, #16]   // buf
    mov x1, #0            // neg flag
    cmp x0, #0
    b.ge .Lsnpi_pos
    neg x0, x0
    mov x1, #1
.Lsnpi_pos:
    str x1, [x29, #32]
    mov x2, #0
    mov x3, #10
.Lsnpi_div:
    udiv x5, x0, x3
    msub x6, x5, x3, x0
    add x6, x6, #48
    str x6, [sp, #-16]!
    add x2, x2, #1
    str x2, [x29, #40]
    mov x0, x5
    cbnz x0, .Lsnpi_div
    // reverse into buf
    ldr x2, [x29, #40]
    ldr x4, [x29, #16]
    mov x7, #0
    ldr x1, [x29, #32]
    cbz x1, .Lsnpi_nosgn
    mov w1, #45
    strb w1, [x4, x7]
    add x7, x7, #1
.Lsnpi_nosgn:
.Lsnpi_rev:
    ldr x6, [sp], #16
    strb w6, [x4, x7]
    add x7, x7, #1
    sub x2, x2, #1
    cbnz x2, .Lsnpi_rev
    mov w6, #0
    strb w6, [x4, x7]
    mov x0, x7
    b .Lsnpf_done

.Lsnpf_float:
    // d0 still holds the value (AAPCS64 keeps it there; nothing above clobbers it). The format
    // is "%.15g" or "%.17g": the second precision digit picks the count.
    ldr x0, [x29, #16]
    ldrb w1, [x2, #3]
    sub w1, w1, #38       // '5' is 15, '7' is 17
    bl _rail_fmt_g
    b .Lsnpf_done

.Lsnpf_done:
    ldp x29, x30, [sp], #48
    ret

// _rail_fmt_g: x0 = buffer, x1 = precision P, d0 = value. Writes what C's "%.<P>g" writes,
// NUL-terminated, and returns the length. Exact: the double is expanded to decimal digits with
// integer arithmetic on 32-bit limbs (no float operation), then rounded half-to-even at P
// significant digits, so the text is the one macOS's libc prints. Leaf: calls nothing.
//
// Written 2026-11-19. What stood here multiplied by 1e6 and printed the integer: six decimals
// at most (show_float (1.0 /. 3.0) gave 0.333333, macOS 0.333333333333333), a saturated
// 9223372036854.775807 for 1.0e21, and 0.1 where show_float_exact owes 0.10000000000000001.
//
// Frame: limbs at sp+0 (40 slots of 8 bytes, one 32-bit limb each), digits around sp+720
// (integer digits grow down from there, fraction digits grow up).
// x13 = first digit, x14 = one past the last, x15 = decimal exponent of the first digit,
// x16 = nonzero when value remains beyond the digits produced.
_rail_fmt_g:
    sub sp, sp, #1408
    mov x17, x0
    mov x8, x0
    fmov x9, d0
    tbz x9, #63, .Lfg_pos
    mov w2, #45
    strb w2, [x17], #1
    and x9, x9, #0x7fffffffffffffff
.Lfg_pos:
    lsr x11, x9, #52
    and x10, x9, #0x000fffffffffffff
    cmp x11, #0x7ff
    b.ne .Lfg_finite
    cbnz x10, .Lfg_nan
    mov w2, #105
    strb w2, [x17], #1
    mov w2, #110
    strb w2, [x17], #1
    mov w2, #102
    strb w2, [x17], #1
    b .Lfg_done
.Lfg_nan:
    mov x17, x8
    mov w2, #110
    strb w2, [x17], #1
    mov w2, #97
    strb w2, [x17], #1
    mov w2, #110
    strb w2, [x17], #1
    b .Lfg_done
.Lfg_finite:
    cbnz x9, .Lfg_nonzero
    mov w2, #48
    strb w2, [x17], #1
    b .Lfg_done
.Lfg_nonzero:
    cbz x11, .Lfg_subnormal
    orr x10, x10, #0x0010000000000000
    sub x11, x11, #1075
    b .Lfg_have_me
.Lfg_subnormal:
    mov x11, #-1074
.Lfg_have_me:
    // value = x10 * 2^x11, x10 below 2^53
    mov x2, #0
.Lfg_zero:
    str xzr, [sp, x2, lsl #3]
    add x2, x2, #1
    cmp x2, #40
    b.lt .Lfg_zero
    add x13, sp, #720
    add x14, sp, #720
    mov x16, #0
    mov x7, #10
    cmp x11, #0
    b.lt .Lfg_frac

    // An integer: x10 << x11 across the limbs, then divide by ten until nothing is left.
    lsr x2, x11, #5
    and x3, x11, #31
    lsl x4, x10, x3
    mov x5, #0
    cbz x3, .Lfg_int_store
    mov x6, #64
    sub x6, x6, x3
    lsr x5, x10, x6
.Lfg_int_store:
    and x6, x4, #0xffffffff
    str x6, [sp, x2, lsl #3]
    add x2, x2, #1
    lsr x6, x4, #32
    str x6, [sp, x2, lsl #3]
    add x2, x2, #1
    str x5, [sp, x2, lsl #3]
.Lfg_idiv:
    mov x3, x2
    mov x4, #0
    mov x5, #0
.Lfg_idiv_limb:
    ldr x6, [sp, x3, lsl #3]
    orr x6, x6, x4, lsl #32
    udiv x12, x6, x7
    msub x4, x12, x7, x6
    str x12, [sp, x3, lsl #3]
    orr x5, x5, x12
    subs x3, x3, #1
    b.ge .Lfg_idiv_limb
    strb w4, [x13, #-1]!
    cbnz x5, .Lfg_idiv
    sub x15, x14, x13
    sub x15, x15, #1
    b .Lfg_round

    // A fraction: k = -e. The whole part fits a register; the rest is F / 2^k with F in the
    // limbs, and each next digit is the part of F * 10 at and above bit k.
.Lfg_frac:
    neg x11, x11
    mov x2, #0
    mov x3, x10
    cmp x11, #53
    b.ge .Lfg_split_done
    lsr x2, x10, x11
    lsl x4, x2, x11
    sub x3, x10, x4
.Lfg_split_done:
    and x4, x3, #0xffffffff
    str x4, [sp]
    lsr x4, x3, #32
    str x4, [sp, #8]
    cbz x2, .Lfg_whole_done
.Lfg_whole:
    udiv x4, x2, x7
    msub x5, x4, x7, x2
    strb w5, [x13, #-1]!
    mov x2, x4
    cbnz x2, .Lfg_whole
.Lfg_whole_done:
    sub x15, x14, x13
    sub x15, x15, #1
    lsr x2, x11, #5          // limb holding bit k
    and x3, x11, #31         // bit k within it
    mov x12, #0              // zeros after the point before the first digit
.Lfg_floop:
    mov x4, #0
    mov x5, #0
.Lfg_fzero:
    ldr x6, [sp, x4, lsl #3]
    orr x5, x5, x6
    add x4, x4, #1
    cmp x4, x2
    b.le .Lfg_fzero
    cbz x5, .Lfg_round       // nothing left: the expansion is exact
    sub x4, x14, x13
    cmp x4, x1
    b.gt .Lfg_fsticky        // P + 1 digits in hand and more would follow
    mov x4, #0
    mov x5, #0
    add x9, x2, #1
.Lfg_fmul:
    ldr x6, [sp, x4, lsl #3]
    madd x6, x6, x7, x5
    and x10, x6, #0xffffffff
    str x10, [sp, x4, lsl #3]
    lsr x5, x6, #32
    add x4, x4, #1
    cmp x4, x9
    b.le .Lfg_fmul
    ldr x4, [sp, x2, lsl #3]
    lsr x5, x4, x3
    ldr x6, [sp, x9, lsl #3]
    mov x10, #32
    sub x10, x10, x3
    lsl x6, x6, x10
    orr x5, x5, x6
    and x5, x5, #15
    mov x6, #1
    lsl x6, x6, x3
    sub x6, x6, #1
    and x4, x4, x6
    str x4, [sp, x2, lsl #3]
    str xzr, [sp, x9, lsl #3]
    cmp x14, x13
    b.ne .Lfg_fstore
    cbnz x5, .Lfg_ffirst
    add x12, x12, #1
    b .Lfg_floop
.Lfg_ffirst:
    mvn x15, x12             // exponent of the first digit: -(zeros + 1)
.Lfg_fstore:
    strb w5, [x14], #1
    b .Lfg_floop
.Lfg_fsticky:
    mov x16, #1

    // Round half to even at P digits.
.Lfg_round:
    sub x2, x14, x13
    cmp x2, x1
    b.le .Lfg_trim
    ldrb w3, [x13, x1]
    add x4, x1, #1
.Lfg_sticky:
    cmp x4, x2
    b.ge .Lfg_sticky_done
    ldrb w5, [x13, x4]
    orr x16, x16, x5
    add x4, x4, #1
    b .Lfg_sticky
.Lfg_sticky_done:
    add x14, x13, x1
    cmp w3, #5
    b.lt .Lfg_trim
    b.gt .Lfg_up
    cbnz x16, .Lfg_up
    ldrb w5, [x14, #-1]
    tbz w5, #0, .Lfg_trim
.Lfg_up:
    mov x4, x14
.Lfg_carry:
    cmp x4, x13
    b.eq .Lfg_carry_out
    ldrb w5, [x4, #-1]!
    add w5, w5, #1
    cmp w5, #10
    b.lt .Lfg_carry_store
    strb wzr, [x4]
    b .Lfg_carry
.Lfg_carry_store:
    strb w5, [x4]
    b .Lfg_trim
.Lfg_carry_out:
    mov w5, #1               // all nines: 1 and zeros, one decade up
    strb w5, [x13]
    add x15, x15, #1
.Lfg_trim:
    sub x2, x14, x13
    cmp x2, #1
    b.le .Lfg_emit
    ldrb w5, [x14, #-1]
    cbnz w5, .Lfg_emit
    sub x14, x14, #1
    b .Lfg_trim

    // %g: scientific when the exponent is below -4 or at least P, else fixed.
.Lfg_emit:
    cmn x15, #4
    b.lt .Lfg_sci
    cmp x15, x1
    b.ge .Lfg_sci
    cmp x15, #0
    b.lt .Lfg_small
    mov x3, #0
.Lfg_fix_whole:
    mov w5, #0
    cmp x3, x2
    b.ge .Lfg_fix_put
    ldrb w5, [x13, x3]
.Lfg_fix_put:
    add w5, w5, #48
    strb w5, [x17], #1
    add x3, x3, #1
    cmp x3, x15
    b.le .Lfg_fix_whole
    cmp x3, x2
    b.ge .Lfg_done
    mov w5, #46
    strb w5, [x17], #1
.Lfg_fix_frac:
    ldrb w5, [x13, x3]
    add w5, w5, #48
    strb w5, [x17], #1
    add x3, x3, #1
    cmp x3, x2
    b.lt .Lfg_fix_frac
    b .Lfg_done
.Lfg_small:
    mov w5, #48
    strb w5, [x17], #1
    mov w5, #46
    strb w5, [x17], #1
    mvn x3, x15
.Lfg_small_zero:
    cbz x3, .Lfg_small_digits
    mov w5, #48
    strb w5, [x17], #1
    sub x3, x3, #1
    b .Lfg_small_zero
.Lfg_small_digits:
    mov x3, #0
.Lfg_small_put:
    ldrb w5, [x13, x3]
    add w5, w5, #48
    strb w5, [x17], #1
    add x3, x3, #1
    cmp x3, x2
    b.lt .Lfg_small_put
    b .Lfg_done
.Lfg_sci:
    ldrb w5, [x13]
    add w5, w5, #48
    strb w5, [x17], #1
    cmp x2, #1
    b.le .Lfg_sci_exp
    mov w5, #46
    strb w5, [x17], #1
    mov x3, #1
.Lfg_sci_put:
    ldrb w5, [x13, x3]
    add w5, w5, #48
    strb w5, [x17], #1
    add x3, x3, #1
    cmp x3, x2
    b.lt .Lfg_sci_put
.Lfg_sci_exp:
    mov w5, #101
    strb w5, [x17], #1
    mov w5, #43
    cmp x15, #0
    b.ge .Lfg_sci_sign
    mov w5, #45
    neg x15, x15
.Lfg_sci_sign:
    strb w5, [x17], #1
    cmp x15, #100
    b.lt .Lfg_sci_two
    mov x4, #100
    udiv x5, x15, x4
    msub x15, x5, x4, x15
    add w5, w5, #48
    strb w5, [x17], #1
.Lfg_sci_two:
    udiv x5, x15, x7
    msub x6, x5, x7, x15
    add w5, w5, #48
    strb w5, [x17], #1
    add w6, w6, #48
    strb w6, [x17], #1
.Lfg_done:
    strb wzr, [x17]
    sub x0, x17, x8
    add sp, sp, #1408
    ret

// 1e6 as IEEE-754 double: 0x412E848000000000.
.section .rodata
.p2align 3
_1e6_f64:
    .quad 0x412E848000000000
.text

// ---- Process exit and square root ----
// _exit: libSystem's on macOS; the collector's out-of-memory path calls it
// (runtime/arm64/gc_2.s) and every Linux link failed on it until 2026-10-21.
_exit:
    mov x8, #93
    svc #0
    b _exit

// _rail_sig_init: the stack overflow handler (runtime/arm64/effects.s) is Darwin syscalls and
// a Darwin signal frame. Not ported: on Linux a runaway recursion still dies by SIGSEGV.
_rail_sig_init:
    ret

// _rail_exit_check: main's epilogue calls it with the exit code in x0. An error raised outside
// `try` and never inspected (runtime/arm64/effects.s) ends the program with exit 1.
_rail_exit_check:
    adrp x1, _rail_err_pending
    ldr x1, [x1, :lo12:_rail_err_pending]
    cmp x1, #0
    b.gt 1f
    ret
1:
    mov x0, #2
    adrp x1, _rail_err_hdr
    add x1, x1, :lo12:_rail_err_hdr
    mov x2, #23
    bl _write
    adrp x0, _rail_err_last
    add x0, x0, :lo12:_rail_err_last
    bl _strlen
    mov x2, x0
    mov x0, #2
    adrp x1, _rail_err_last
    add x1, x1, :lo12:_rail_err_last
    bl _write
    mov x0, #2
    adrp x1, _rail_err_nl
    add x1, x1, :lo12:_rail_err_nl
    mov x2, #1
    bl _write
    mov x0, #1
    b _exit

// _sqrt: IEEE-754 requires a correctly rounded square root, so the instruction and
// libm's sqrt give the same bits; the kernel's `sqrt` compiles to `bl _sqrt` and links
// here on Linux. `sin` has no Linux implementation: a program that calls it is declared
// non-replay on this target until Tier 3 step 4 (rail-plasma docs/REPLAY.md).
_sqrt:
    fsqrt d0, d0
    ret

// ---- float32 file I/O (runtime/arm64/float.s, Linux syscalls) ----
// The macOS versions issue raw Darwin syscalls (svc #0x80 with x16 = 0x2000005 open,
// 0x2000004 write, 0x2000003 read, 0x2000006 close), which Linux does not understand: the
// writer's open failed, it returned false, and nothing was written. Found 2026-10-21 (Tier 3,
// step 8): the beacon replay on a Pi had been digesting 393,216 zero bytes and reporting a
// mismatch that looked numerical. build_linux strips the macOS pair; these take their place.
// Same frames, same conversions (fcvt s0, d0 and back), same return values: 3 (true) on
// success, 1 (false) when the open fails. A single read, as on macOS.
// float_arr_to_f32_file: x0 = path (str), x1 = arr, x2 = n (tagged). Writes n float32 values.
_rail_float_arr_to_f32_file:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [x29, #48]
    str x21, [x29, #64]
    str x1, [x29, #16]
    asr x2, x2, #1
    str x2, [x29, #24]
    bl _str_unwrap
    mov x1, x0                    // path
    mov x0, #-100                 // AT_FDCWD
    mov x2, #0x241                // O_WRONLY|O_CREAT|O_TRUNC (Linux bits)
    mov x3, #0x1b6                // 0666
    mov x8, #56                   // openat
    svc #0
    cmp x0, #0
    b.lt .Llf32w_err
    str x0, [x29, #32]
    ldr x21, [x29, #24]
    lsl x0, x21, #2
    bl _rail_chained_malloc
    str x0, [x29, #40]
    mov x19, #0
    ldr x20, [x29, #16]
.Llf32w_loop:
    cmp x19, x21
    b.hs .Llf32w_done
    add x6, x19, #1
    ldr d0, [x20, x6, lsl #3]
    fcvt s0, d0
    ldr x7, [x29, #40]
    lsl x8, x19, #2
    str s0, [x7, x8]
    add x19, x19, #1
    b .Llf32w_loop
.Llf32w_done:
    ldr x0, [x29, #32]
    ldr x1, [x29, #40]
    lsl x2, x21, #2
    mov x8, #64                   // write
    svc #0
    ldr x0, [x29, #32]
    mov x8, #57                   // close
    svc #0
    mov x0, #3
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret
.Llf32w_err:
    mov x0, #1
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret

// float_arr_from_f32_file: x0 = path (str), x1 = arr, x2 = n (tagged). Reads n float32 values.
_rail_float_arr_from_f32_file:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [x29, #48]
    str x21, [x29, #64]
    str x1, [x29, #16]
    asr x2, x2, #1
    str x2, [x29, #24]
    bl _str_unwrap
    mov x1, x0                    // path
    mov x0, #-100                 // AT_FDCWD
    mov x2, #0                    // O_RDONLY
    mov x3, #0
    mov x8, #56                   // openat
    svc #0
    cmp x0, #0
    b.lt .Llf32r_err
    str x0, [x29, #32]
    ldr x21, [x29, #24]
    lsl x0, x21, #2
    bl _rail_chained_malloc
    str x0, [x29, #40]
    ldr x0, [x29, #32]
    ldr x1, [x29, #40]
    lsl x2, x21, #2
    mov x8, #63                   // read
    svc #0
    mov x19, #0
    ldr x20, [x29, #16]
.Llf32r_loop:
    cmp x19, x21
    b.hs .Llf32r_done
    ldr x7, [x29, #40]
    lsl x8, x19, #2
    ldr s0, [x7, x8]
    fcvt d0, s0
    add x6, x19, #1
    str d0, [x20, x6, lsl #3]
    add x19, x19, #1
    b .Llf32r_loop
.Llf32r_done:
    ldr x0, [x29, #32]
    mov x8, #57                   // close
    svc #0
    mov x0, #3
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret
.Llf32r_err:
    mov x0, #1
    ldp x19, x20, [x29, #48]
    ldr x21, [x29, #64]
    ldp x29, x30, [sp], #80
    ret

// ---- File I/O via syscalls ----

_fopen:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldrb w2, [x1]
    cmp w2, #119          // 'w'
    b.eq .Lfop_w
    cmp w2, #97           // 'a'
    b.eq .Lfop_a
    // default: read
    mov x1, x0
    mov x0, #-100         // AT_FDCWD
    mov x2, #0            // O_RDONLY
    mov x3, #0
    mov x8, #56           // openat
    svc #0
    b .Lfop_done
.Lfop_w:
    mov x1, x0
    mov x0, #-100
    mov x2, #0x241        // O_WRONLY|O_CREAT|O_TRUNC
    mov x3, #0x1a4        // 0644
    mov x8, #56
    svc #0
    b .Lfop_done
.Lfop_a:
    mov x1, x0
    mov x0, #-100
    mov x2, #0x441        // O_WRONLY|O_CREAT|O_APPEND
    mov x3, #0x1a4        // 0644
    mov x8, #56
    svc #0
.Lfop_done:
    cmp x0, #0
    b.ge .Lfop_ok
    mov x0, #0
.Lfop_ok:
    ldp x29, x30, [sp], #16
    ret

// _fwrite(ptr, size, nmemb, fd) -> bytes_written
// Linux write(2) can return short under memory/pipe pressure. Looping until
// count==0 (or error) is required for full-content delivery — the legacy
// single-call version silently truncated .s output on Pi when the kernel
// short-returned. Returns total bytes written.
_fwrite:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mul x2, x1, x2        // x2 = size*nmemb = total bytes
    mov x1, x0            // x1 = buf
    mov x0, x3            // x0 = fd
    str x0, [sp, #16]     // save fd
    str xzr, [sp, #24]    // total_written = 0
.Lfw_loop:
    cbz x2, .Lfw_done
    mov x8, #64           // SYS_write
    svc #0
    tst x0, x0
    b.mi .Lfw_done        // negative = -errno, return as-is
    ldr x4, [sp, #24]
    add x4, x4, x0
    str x4, [sp, #24]
    add x1, x1, x0        // buf += written
    subs x2, x2, x0       // remaining -= written
    b.eq .Lfw_done
    ldr x0, [sp, #16]     // reload fd
    b .Lfw_loop
.Lfw_done:
    ldr x0, [sp, #24]     // return total
    ldp x29, x30, [sp], #32
    ret

_fread:
    mul x2, x1, x2
    mov x1, x0
    mov x0, x3
    mov x8, #63           // read
    svc #0
    ret

_fclose:
    mov x8, #57           // close
    svc #0
    ret

_fseek:
    mov x8, #62           // lseek
    svc #0
    mov x0, #0
    ret

_ftell:
    mov x1, #0
    mov x2, #1            // SEEK_CUR
    mov x8, #62
    svc #0
    ret

_fflush:
    mov x0, #0
    ret

_open:
    mov x3, #0x1B6
    mov x2, x1
    mov x1, x0
    mov x0, #-100
    mov x8, #56
    svc #0
    ret

_ioctl:
    mov x8, #29
    svc #0
    ret

_sys_write:
    mov x8, #64
    svc #0
    ret

_sys_close:
    mov x8, #57
    svc #0
    ret

_usleep:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov x1, #1000
    mul x1, x0, x1
    mov x0, #0
    stp x0, x1, [x29, #16]
    add x0, x29, #16
    mov x1, #0
    mov x8, #101
    svc #0
    ldp x29, x30, [sp], #32
    ret

_poke_byte:
    strb w2, [x0, x1]
    mov x0, #0
    ret

_peek_byte:
    ldrb w0, [x0, x1]
    ret

_memset2:
    cbz x3, .Lms2_done
.Lms2_loop:
    strb w1, [x0], #1
    strb w2, [x0], #1
    sub x3, x3, #1
    cbnz x3, .Lms2_loop
.Lms2_done:
    mov x0, #0
    ret

// ---- popen/pclose: fork + execve + pipe ----

_popen:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    str x0, [x29, #16]    // cmd
    // pipe2(fds, 0)
    add x0, x29, #24
    mov x1, #0
    mov x8, #59
    svc #0
    // clone(SIGCHLD, 0, 0, 0, 0)
    mov x0, #0x11
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, #220
    svc #0
    cbnz x0, .Lpop_parent
    // Child: dup2 write end → stdout
    ldr w0, [x29, #28]
    mov x1, #1
    mov x8, #24            // dup3
    svc #0
    ldr w0, [x29, #24]
    mov x8, #57
    svc #0
    ldr w0, [x29, #28]
    mov x8, #57
    svc #0
    // execve("/bin/sh", ["/bin/sh", "-c", cmd, NULL], NULL)
    b .Lpop_ashell
.Lpop_shell:
    .asciz "/bin/sh"
    .p2align 2
.Lpop_cflag:
    .asciz "-c"
    .p2align 2
.Lpop_ashell:
    adr x0, .Lpop_shell
    str x0, [x29, #40]
    adr x1, .Lpop_cflag
    str x1, [x29, #48]
    ldr x2, [x29, #16]
    str x2, [x29, #56]
    str xzr, [x29, #64]
    adr x0, .Lpop_shell
    add x1, x29, #40
    mov x2, #0
    mov x8, #221           // execve
    svc #0
    mov x0, #1
    mov x8, #93
    svc #0
.Lpop_parent:
    str x0, [x29, #32]
    ldr w0, [x29, #28]
    mov x8, #57
    svc #0
    ldr w0, [x29, #24]
    ldp x29, x30, [sp], #80
    ret

_pclose:
    mov x8, #57
    svc #0
    mov x0, #-1
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x8, #260           // wait4
    svc #0
    ret


// ============ Networking syscalls (added for dns-sink, 2026-04-07) ============
//
// All Linux ARM64 syscalls follow the convention:
//   syscall nr in x8, args in x0..x5, svc #0, return in x0.
// The Rail FFI ABI already places call args in x0..x5 (System V on Linux),
// so each wrapper just sets x8 and traps. Return value flows back in x0
// where Rail's FFI codegen will retag it as a tagged int.
//
// Syscall numbers from /usr/include/asm-generic/unistd.h:
//   close=57  socket=198  bind=200  listen=201  accept4=242  connect=203
//   sendto=206  recvfrom=207  setsockopt=208  clock_gettime=113

_close:
    mov x8, #57
    svc #0
    ret

_socket:
    mov x8, #198
    svc #0
    ret

_bind:
    mov x8, #200
    svc #0
    ret

_listen:
    mov x8, #201
    svc #0
    ret

_connect:
    mov x8, #203
    svc #0
    ret

_accept4:
    mov x8, #242
    svc #0
    ret

_sendto:
    mov x8, #206
    svc #0
    ret

_recvfrom:
    mov x8, #207
    svc #0
    ret

_setsockopt:
    mov x8, #208
    svc #0
    ret

// ============ Byte-order helpers (not syscalls) ============

// htons(x): swap the low 16 bits of x.
// rev16 reverses bytes within each 16-bit halfword of the source.
_htons:
    and x0, x0, #0xFFFF
    rev16 w0, w0
    and x0, x0, #0xFFFF
    ret

// htonl(x): swap the bytes of the low 32 bits of x.
_htonl:
    and x0, x0, #0xFFFFFFFF
    rev w0, w0
    and x0, x0, #0xFFFFFFFF
    ret

// ============ time wrapper ============
//
// Linux ARM64 has no time() syscall — use clock_gettime(CLOCK_REALTIME, &ts)
// and return ts.tv_sec. Caller's t arg (x0) is ignored (we never write
// it back; Rail callers always pass NULL).
_time:
    sub sp, sp, #16          // 16-byte aligned timespec on stack
    mov x0, #0               // CLOCK_REALTIME
    mov x1, sp               // &timespec
    mov x8, #113             // clock_gettime
    svc #0
    ldr x0, [sp]             // tv_sec
    add sp, sp, #16
    ret

// ============ sleep (proper kernel sleep, no fork) ============
//
// sleep(seconds) — blocks for N seconds via nanosleep(2).
// Used by dns-sink LCD instead of shell "sleep N" which forks.
_sleep:
    sub sp, sp, #16
    str x0, [sp]              // req.tv_sec = seconds
    str xzr, [sp, #8]        // req.tv_nsec = 0
    mov x0, sp               // req
    mov x1, #0               // rem = NULL
    mov x8, #101             // nanosleep
    svc #0
    add sp, sp, #16
    mov x0, #0               // return 0
    ret

// ============ clock_ms (monotonic millisecond clock) ============
//
// clock_ms() — returns current time in milliseconds (CLOCK_MONOTONIC).
// Used by dns-sink to measure upstream query latency.
_clock_ms:
    sub sp, sp, #16
    mov x0, #1               // CLOCK_MONOTONIC
    mov x1, sp               // &timespec
    mov x8, #113             // clock_gettime
    svc #0
    ldr x0, [sp]             // tv_sec
    ldr x1, [sp, #8]         // tv_nsec
    add sp, sp, #16
    mov x2, #1000
    mul x0, x0, x2           // sec * 1000
    udiv x1, x1, x2          // nsec / 1000 = usec
    udiv x1, x1, x2          // usec / 1000 = ms remainder
    add x0, x0, x1           // total ms
    ret

// ============ Threads, mutexes, try ============
//
// Until 2026-11-19 these were stubs written for dns-sink, which calls none of them: _setjmp
// returned 0 and _longjmp exited 1, so an error raised inside `try` ended the program in silence
// with status 1 instead of running the handler, and _pthread_create returned -1, which
// spawn_thread took for a handle and join_thread then dereferenced (SIGSEGV). Measured on a
// Pi Zero 2 W (aarch64 Linux). setjmp and longjmp are real now. Threads are still not built
// here (no libc: it would take clone, a stack and a futex join), so spawn_thread says so and
// exits 1 rather than crashing later.

_pthread_create:
    mov x0, #2
    adr x1, .Lno_threads_msg
    mov x2, #51
    mov x8, #64              // write
    svc #0
    mov x0, #1
    mov x8, #93              // exit
    svc #0
.Lno_threads_msg:
    .ascii "rail: spawn_thread is not supported on Linux ARM64\n"
    .p2align 2

_pthread_join:
    mov x0, #-1
    ret

// Nothing can contend without threads; the mutex calls succeed.
_pthread_mutex_init:
    mov x0, #0
    ret

// The allocator takes this mutex only while a thread is live, which never happens here.
_pthread_mutex_lock:
    mov x0, #0
    ret

_pthread_mutex_unlock:
    mov x0, #0
    ret

// jmp_buf (the runtime gives it 200 bytes): x19..x30 at 0..88, sp at 96, d8..d15 at 104..160.
_setjmp:
    stp x19, x20, [x0, #0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x2, sp
    str x2, [x0, #96]
    stp d8, d9, [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]
    mov x0, #0
    ret

_longjmp:
    ldp x19, x20, [x0, #0]
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
    cmp x1, #0
    csinc x0, x1, xzr, ne    // setjmp returns the value, or 1 when asked for 0
    ret

// ============ Bump-allocated _malloc replacement ============
//
// Patched 2026-04-08: the original _malloc was a thin mmap wrapper —
// every call did its own syscall, getting a fresh 4 KB page minimum.
// _rail_split allocates one buffer per substring. For an oisd 56 k-domain
// blocklist that meant 56 k * 4 KB = 224 MB physical, OOM-killing the Pi.
//
// The Rail-compiled binary already has a 512 MB virtual bump arena
// (_rail_heap + _rail_heap_ptr) used by _rail_alloc for cons cells / tuples
// / closures. We share that same arena for _malloc.
//
// _malloc — separate-pool bump allocator for Linux.
//
// Earlier impl piggybacked on _rail_heap_ptr (the same bump pointer
// _rail_alloc uses), so arena_reset would roll the pointer back through
// chunks that _rail_chained_malloc had pushed onto its small free-list
// (_rail_small_fl). Iter 2's recv buffer would then overwrite those
// chunks; the next chained_malloc small-bin pop read garbage out of
// chunk[0] and either crashed at `ldr x7, [x6]` (when the garbage
// looked like a small/junk pointer like 0x1) or kept walking corrupt
// state until it tripped a NULL deref.
//
// Mac's _malloc uses _rail_malloc_ptr / _rail_malloc_end — a separate
// 4 MB-chunked pool that arena_reset never touches. Match that.
// _rail_malloc_ptr / _rail_malloc_end are declared in compile.rail's
// data section, both initialized to 0 (lazy-init on first call).
_malloc:
    // x0 = requested size in bytes.
    add x9, x0, #15
    and x9, x9, #-16
    cmp x9, #0x10000              // 65536
    b.hi .Lmalloc_large_l
    str x9, [sp, #-16]!
    // Load _rail_malloc_ptr; if NULL, fall through to newpage.
    adrp x10, _rail_malloc_ptr
    add x10, x10, :lo12:_rail_malloc_ptr
    ldr x11, [x10]
    cbz x11, .Lmalloc_newpage_l
    add x12, x11, x9
    adrp x13, _rail_malloc_end
    add x13, x13, :lo12:_rail_malloc_end
    ldr x13, [x13]
    cmp x12, x13
    b.hi .Lmalloc_newpage_l
    str x12, [x10]
    add sp, sp, #16
    mov x0, x11
    ret
.Lmalloc_newpage_l:
    // mmap 4 MB, set _rail_malloc_ptr = base + size, end = base + 4 MB.
    mov x0, #0
    mov x1, #0x400000
    mov x2, #3
    mov x3, #0x22                 // MAP_PRIVATE|MAP_ANONYMOUS (Linux)
    mov x4, #-1
    mov x5, #0
    mov x8, #222                  // mmap
    svc #0
    cmn x0, #4095
    b.hs .Lmalloc_fail_l
    ldr x9, [sp], #16
    adrp x10, _rail_malloc_ptr
    add x10, x10, :lo12:_rail_malloc_ptr
    add x11, x0, x9
    str x11, [x10]
    adrp x10, _rail_malloc_end
    add x10, x10, :lo12:_rail_malloc_end
    add x11, x0, #0x400000
    str x11, [x10]
    ret
.Lmalloc_large_l:
    // size > 64K: direct mmap. The chained-malloc chain walker (Lmdrn_l)
    // will munmap this chunk on arena_reset.
    mov x1, x9
    mov x0, #0
    mov x2, #3
    mov x3, #0x22
    mov x4, #-1
    mov x5, #0
    mov x8, #222
    svc #0
    cmn x0, #4095
    b.hs .Lmalloc_fail_l
    ret
.Lmalloc_fail_l:
    mov x0, #0
    ret

// ============ fputs (used by dns/log.rail) ============
//
// int fputs(const char *s, FILE *fp)
// Writes the C string to fp via fwrite. Returns whatever fwrite returns.
_fputs:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]   // save s
    str x1, [x29, #24]   // save fp
    bl _strlen            // x0 = strlen(s)
    mov x2, x0            // count = strlen(s)
    ldr x0, [x29, #16]    // ptr = s
    mov x1, #1            // size = 1
    ldr x3, [x29, #24]    // FILE* = fp
    bl _fwrite
    ldp x29, x30, [sp], #32
    ret

// ============ Cross-compile additions (2026-04-17) ============

// accept(fd, addr, addrlen) — wrap accept4 with flags=0
// Linux ARM64 dropped legacy accept (202); use accept4 (242) with 0 flags.
_accept:
    mov x3, #0           // flags = 0
    mov x8, #242         // accept4
    svc #0
    ret

// send(fd, buf, len, flags) — wrap sendto with NULL dest
_send:
    mov x4, #0           // dest_addr = NULL
    mov x5, #0           // addrlen = 0
    mov x8, #206         // sendto
    svc #0
    ret

// recv(fd, buf, len, flags) — wrap recvfrom with NULL src
_recv:
    mov x4, #0           // src_addr = NULL
    mov x5, #0           // addrlen = NULL
    mov x8, #207         // recvfrom
    svc #0
    ret

// strtol(nptr, endptr, base) — Rail's parse_int primitive emits `bl _strtol`.
// We support base 10 (matching the compiler's `mov x2, #10`). endptr ignored.
// Skips leading whitespace, optional +/- sign, then digits.
_strtol:
    mov x9, x0           // x9 = ptr
    mov x10, #0          // result
    mov x11, #1          // sign
.Lstrtol_skipws:
    ldrb w12, [x9]
    cmp w12, #32         // ' '
    b.eq .Lstrtol_advws
    cmp w12, #9          // '\t'
    b.ne .Lstrtol_sign
.Lstrtol_advws:
    add x9, x9, #1
    b .Lstrtol_skipws
.Lstrtol_sign:
    cmp w12, #45         // '-'
    b.ne .Lstrtol_plus
    mov x11, #-1
    add x9, x9, #1
    b .Lstrtol_loop
.Lstrtol_plus:
    cmp w12, #43         // '+'
    b.ne .Lstrtol_loop
    add x9, x9, #1
.Lstrtol_loop:
    ldrb w12, [x9]
    cmp w12, #48         // '0'
    b.lt .Lstrtol_done
    cmp w12, #57         // '9'
    b.gt .Lstrtol_done
    sub w12, w12, #48
    mov x13, #10
    mul x10, x10, x13
    add x10, x10, x12
    add x9, x9, #1
    b .Lstrtol_loop
.Lstrtol_done:
    mul x0, x10, x11
    ret

// memcpy(dst=x0, src=x1, n=x2) → x0  (returns original dst).
// Naive byte copy.  Used by _rail_str_append and _rail_join on Linux.
_memcpy:
    mov x4, x0          // save dst
    cbz x2, .Lmemcpy_done
.Lmemcpy_loop:
    ldrb w3, [x1], #1
    strb w3, [x0], #1
    sub x2, x2, #1
    cbnz x2, .Lmemcpy_loop
.Lmemcpy_done:
    mov x0, x4
    ret

// fmod(a=d0, b=d1) → d0  (a mod b for doubles).
// Truncation-toward-zero variant: r = a - trunc(a/b) * b.
// Sufficient for Rail's modulo-on-floats use case (not IEEE-precise edge).
_fmod:
    fdiv d2, d0, d1
    fcvtzs x3, d2
    scvtf d2, x3
    fmul d2, d2, d1
    fsub d0, d0, d2
    ret

// BSS reservations for young-generation semispace GC.
// Mac codegen declares these via .zerofill which the transform sed strips.
// .comm provides equivalent BSS allocation in ELF.
.comm _rail_young_a, 67108864, 8
.comm _rail_young_b, 67108864, 8
