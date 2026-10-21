// rt_arena: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
// A1.P4: runtime mmap arena. Replaces static BSS _rail_heap. Called from
// macOS __mod_init_func (runs before main). Reads RAIL_ARENA_MB env var
// (default 1024 = 1GB). On macOS dyld load layout, static BSS > 1GB breaks
// dyld ("dyld cache not loaded"); runtime mmap sidesteps this.
//@ literal
_rail_arena_init:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    adrp x0, _rail_arena_env_name@PAGE
    add x0, x0, _rail_arena_env_name@PAGEOFF
    bl _getenv
    cbz x0, .Larenain_default
    bl _atoi
    cmp x0, #1
    b.lt .Larenain_default
    lsl x0, x0, #20
    b .Larenain_alloc
.Larenain_default:
    mov x0, #0x4000
    lsl x0, x0, #16
.Larenain_alloc:
    str x0, [x29, #16]
    mov x1, #1
    lsl x1, x1, #36
    cmp x0, x1
    csel x1, x0, x1, hi
    str x1, [x29, #24]
    mov x0, #0
    mov x2, #3
    mov x3, #0x1002
    mov x4, #-1
    mov x5, #0
    movz x16, #197
    movk x16, #0x200, lsl #16
    svc #0x80
    b.cs .Larenain_fail
    adrp x1, _rail_heap_base@PAGE
    add x1, x1, _rail_heap_base@PAGEOFF
    str x0, [x1]
    adrp x1, _rail_heap_ptr@PAGE
    add x1, x1, _rail_heap_ptr@PAGEOFF
    str x0, [x1]
    ldr x2, [x29, #16]
    add x3, x0, x2
    adrp x1, _rail_heap_end@PAGE
    add x1, x1, _rail_heap_end@PAGEOFF
    str x3, [x1]
    ldr x2, [x29, #24]
    add x3, x0, x2
    adrp x1, _rail_heap_limit@PAGE
    add x1, x1, _rail_heap_limit@PAGEOFF
    str x3, [x1]
    adrp x0, _rail_arena_trace_env@PAGE
    add x0, x0, _rail_arena_trace_env@PAGEOFF
    bl _getenv
    cbz x0, .Larenain_done
    adrp x1, _rail_arena_trace_flag@PAGE
    add x1, x1, _rail_arena_trace_flag@PAGEOFF
    mov x2, #1
    str x2, [x1]
.Larenain_done:
    adrp x0, _rail_gc_stress_env@PAGE
    add x0, x0, _rail_gc_stress_env@PAGEOFF
    bl _getenv
    cbz x0, .Larenain_ret
    bl _atoi
    cmp x0, #1
    b.lt .Larenain_ret
    adrp x1, _rail_gc_stress@PAGE
    str x0, [x1, _rail_gc_stress@PAGEOFF]
    adrp x1, _rail_gc_stress_left@PAGE
    str x0, [x1, _rail_gc_stress_left@PAGEOFF]
.Larenain_ret:
    ldp x29, x30, [sp], #32
    ret
.Larenain_fail:
    mov x0, #1
    movz x16, #1
    movk x16, #0x200, lsl #16
    svc #0x80

