// rt_effects: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// Effect handlers: try/catch with setjmp/longjmp
// Handler frame: malloc'd block [prev_handler(8), jmp_buf(25*8=200), error_val(8)]
// _rail_try: x0=body_closure, x1=handler_closure → result
// If body calls error, longjmp unwinds to handler
//@ let rtry
_rail_try:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    mov x0, #216
    bl _malloc
    str x0, [x29, #32]
    adrp x1, _rail_handler_top@PAGE
    add x1, x1, _rail_handler_top@PAGEOFF
    ldr x2, [x1]
    str x2, [x0]
    str x0, [x1]
    add x0, x0, #8
    bl _setjmp
    cbnz x0, .Ltry_caught
    ldr x15, [x29, #16]
    ldr x16, [x15, #8]
    mov x0, #1
    blr x16
    str x0, [x29, #40]
    ldr x0, [x29, #32]
    ldr x1, [x0]
    adrp x2, _rail_handler_top@PAGE
    add x2, x2, _rail_handler_top@PAGEOFF
    str x1, [x2]
    ldr x0, [x29, #32]
    bl _free
    ldr x0, [x29, #40]
    ldp x29, x30, [sp], #64
    ret
.Ltry_caught:
    ldr x0, [x29, #32]
    ldr x3, [x0, #208]
    str x3, [x29, #48]
    ldr x1, [x0]
    adrp x2, _rail_handler_top@PAGE
    add x2, x2, _rail_handler_top@PAGEOFF
    str x1, [x2]
    ldr x0, [x29, #32]
    bl _free
    ldr x15, [x29, #24]
    ldr x16, [x15, #8]
    ldr x0, [x29, #48]
    blr x16
    ldp x29, x30, [sp], #64
    ret

// _rail_raise: x0=error_msg_string. Inside a `try`: longjmp to the handler, no return.
// Outside one: returns an error object and counts it as pending (see _rail_err_seen below).
//@ let rraise
_rail_raise:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    adrp x1, _rail_handler_top@PAGE
    add x1, x1, _rail_handler_top@PAGEOFF
    ldr x2, [x1]
    cbz x2, .Lraise_nohandler
    ldr x0, [x29, #16]
    str x0, [x2, #208]
    add x0, x2, #8
    mov x1, #1
    bl _longjmp
.Lraise_nohandler:
    adrp x1, _rail_err_last@PAGE
    add x1, x1, _rail_err_last@PAGEOFF
    mov w3, #0
    strb w3, [x1]
    ldr x0, [x29, #16]
    tst x0, #1
    b.ne .Lraise_count
    bl _str_unwrap
    adrp x1, _rail_err_last@PAGE
    add x1, x1, _rail_err_last@PAGEOFF
    mov x2, #0
.Lraise_cp:
    ldrb w3, [x0, x2]
    strb w3, [x1, x2]
    cbz w3, .Lraise_count
    add x2, x2, #1
    cmp x2, #255
    b.lo .Lraise_cp
    mov w3, #0
    strb w3, [x1, x2]
.Lraise_count:
    adrp x1, _rail_err_pending@PAGE
    add x1, x1, _rail_err_pending@PAGEOFF
    ldr x2, [x1]
    add x2, x2, #1
    str x2, [x1]
    mov x0, #24
    bl _rail_alloc
    mov x1, #8
    str x1, [x0]
    ldr x1, [x29, #16]
    str x1, [x0, #8]
    mov x1, #1
    str x1, [x0, #16]
    ldp x29, x30, [sp], #32
    ret

// An error nobody looked at (2026-11-19). With no `try` around it, `error` returns a value and
// the program carries on; that is how `is_error` works and the auth verifiers depend on it.
// But a value that is never inspected was a silent failure: the program finished with exit 0.
// The error object is [tag 8, message, seen]; seen starts as the tagged int 0 and
// _rail_raise counts the object in _rail_err_pending. is_error (when true) and err_msg call
// _rail_err_seen, which marks it and takes it off the count. main's epilogue calls
// _rail_exit_check with the exit code in x0: a count above zero prints
// `rail: unhandled error: <message of the last one raised>` and exits 1. The message is copied
// (255 bytes at most) when raised, so the report does not depend on the collector. The count
// is not atomic: errors raised on spawned threads at the same moment can miscount.
//@ let rerr
_rail_err_seen:
    tst x0, #1
    b.ne .Lerr_seen_ret
    ldr x1, [x0]
    and x1, x1, #0x7fffffffffffffff
    cmp x1, #8
    b.ne .Lerr_seen_ret
    ldr x1, [x0, #16]
    cmp x1, #1
    b.ne .Lerr_seen_ret
    mov x1, #3
    str x1, [x0, #16]
    adrp x1, _rail_err_pending@PAGE
    add x1, x1, _rail_err_pending@PAGEOFF
    ldr x2, [x1]
    sub x2, x2, #1
    str x2, [x1]
.Lerr_seen_ret:
    ret
_rail_exit_check:
    adrp x1, _rail_err_pending@PAGE
    ldr x1, [x1, _rail_err_pending@PAGEOFF]
    cmp x1, #0
    b.gt .Lexit_report
    ret
.Lexit_report:
    mov x0, #2
    adrp x1, _rail_err_hdr@PAGE
    add x1, x1, _rail_err_hdr@PAGEOFF
    mov x2, #23
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    adrp x0, _rail_err_last@PAGE
    add x0, x0, _rail_err_last@PAGEOFF
    bl _strlen
    mov x2, x0
    mov x0, #2
    adrp x1, _rail_err_last@PAGE
    add x1, x1, _rail_err_last@PAGEOFF
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #2
    adrp x1, _rail_err_nl@PAGE
    add x1, x1, _rail_err_nl@PAGEOFF
    mov x2, #1
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #1
    bl _exit
.data
_rail_err_hdr:
    .asciz "rail: unhandled error: "
_rail_err_nl:
    .asciz "\n"
.p2align 3
_rail_err_pending:
    .quad 0
_rail_err_last:
    .space 256
.p2align 3
.text

// Stack overflow (2026-11-19). Unbounded recursion ran off the 256 MB main stack and died as a
// bare `Bus error`. _rail_sig_init (called from main's prologue, after _rail_stack_top is set)
// maps a 64 KB alternate stack and installs one handler for SIGSEGV and SIGBUS. A fault whose
// address lies in the main stack's range or the megabyte under it prints `rail: stack
// overflow` and exits 1. Any other fault is sent again with the default action restored
// (SA_RESETHAND), so a wild pointer still dies by its signal and a caller still sees 138/139.
// Raw Darwin syscalls: mmap 197, sigaltstack 53, sigaction 46, getpid 20, kill 37. The kernel
// enters sa_tramp with x2 = signal and x3 = siginfo (si_addr at +24); the handler never
// returns, so it is its own trampoline. A spawned thread has no alternate stack: its overflow
// faults again inside the handler and dies by the signal, as before.
//@ let rsig
_rail_sig_init:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    mov x0, #0
    mov x1, #65536
    mov x2, #3
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    movz x16, #197
    movk x16, #0x200, lsl #16
    svc #0x80
    b.cs .Lsig_init_done
    str x0, [x29, #16]
    mov x1, #65536
    str x1, [x29, #24]
    str xzr, [x29, #32]
    add x0, x29, #16
    mov x1, #0
    movz x16, #53
    movk x16, #0x200, lsl #16
    svc #0x80
    b.cs .Lsig_init_done
    adrp x2, _rail_sig_handler@PAGE
    add x2, x2, _rail_sig_handler@PAGEOFF
    str x2, [x29, #40]
    str x2, [x29, #48]
    mov x2, #0x55
    lsl x2, x2, #32
    str x2, [x29, #56]
    mov x0, #11
    add x1, x29, #40
    mov x2, #0
    movz x16, #46
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #10
    add x1, x29, #40
    mov x2, #0
    movz x16, #46
    movk x16, #0x200, lsl #16
    svc #0x80
.Lsig_init_done:
    ldp x29, x30, [sp], #64
    ret
_rail_sig_handler:
    mov x19, x2
    ldr x9, [x3, #24]
    adrp x10, _rail_stack_top@PAGE
    ldr x10, [x10, _rail_stack_top@PAGEOFF]
    cbz x10, .Lsig_other
    cmp x9, x10
    b.hs .Lsig_other
    movz x11, #0x1010, lsl #16
    sub x10, x10, x11
    cmp x9, x10
    b.lo .Lsig_other
    mov x0, #2
    adrp x1, _rail_sig_msg@PAGE
    add x1, x1, _rail_sig_msg@PAGEOFF
    mov x2, #21
    movz x16, #4
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #1
    movz x16, #1
    movk x16, #0x200, lsl #16
    svc #0x80
.Lsig_other:
    movz x16, #20
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x1, x19
    mov x2, #1
    movz x16, #37
    movk x16, #0x200, lsl #16
    svc #0x80
    mov x0, #1
    movz x16, #1
    movk x16, #0x200, lsl #16
    svc #0x80
.data
_rail_sig_msg:
    .asciz "rail: stack overflow\n"
.p2align 3
.text

//@ cat rtry, rraise, rerr, rsig
