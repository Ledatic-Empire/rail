// rt_gpu: see runtime/arm64/README.md for how this file becomes the compiler's runtime.
//@ let rgpumap
_rail_gpu_map:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    str x0, [x29, #16]
    str x1, [x29, #24]
    mov x0, x1
    bl _rail_length
    str x0, [x29, #32]
    b .Lgm_ap
.Lgm_mp:
    .asciz "/tmp/rail_gpu.metal"
    .p2align 2
.Lgm_ap:
    adr x0, .Lgm_mp
    ldr x1, [x29, #16]
    bl _rail_write_file
    b .Lgm_ac
.Lgm_cc:
    .asciz "xcrun metal -c /tmp/rail_gpu.metal -o /tmp/rail_gpu.air 2>/dev/null && xcrun metallib /tmp/rail_gpu.air -o /tmp/rail_gpu.metallib 2>/dev/null"
    .p2align 2
.Lgm_ac:
    adr x0, .Lgm_cc
    bl _rail_shell
    ldr x0, [x29, #32]
    bl _rail_show
    str x0, [x29, #40]
    b .Lgm_ahp
.Lgm_hp:
    .asciz "/tmp/gpu_host /tmp/rail_gpu.metallib rail_kernel "
    .p2align 2
.Lgm_ahp:
    adr x0, .Lgm_hp
    ldr x1, [x29, #40]
    bl _rail_str_append
    bl _rail_shell
    str x0, [x29, #48]
    b .Lgm_arf
.Lgm_rf:
    .asciz "/tmp/rail_gpu_out.csv"
    .p2align 2
.Lgm_arf:
    adr x0, .Lgm_rf
    bl _rail_read_file
    str x0, [x29, #48]
    b .Lgm_acm
.Lgm_cm:
    .asciz ","
    .p2align 2
.Lgm_acm:
    adr x0, .Lgm_cm
    ldr x1, [x29, #48]
    bl _rail_split
    bl _rail_parse_int_list
    ldp x29, x30, [sp], #64
    ret

//@ let rparselist
_rail_parse_int_list:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x0, [x29, #16]
    ldr x1, [x0]
    cmp x1, #2
    b.eq .Lpil_nil
    ldr x1, [x0, #8]
    str x1, [x29, #24]
    ldr x0, [x0, #16]
    bl _rail_parse_int_list
    str x0, [sp, #-16]!
    ldr x0, [x29, #24]
    bl _str_unwrap
    bl _atoi
    lsl x0, x0, #1
    orr x0, x0, #1
    ldr x1, [sp], #16
    bl _rail_cons
    ldp x29, x30, [sp], #32
    ret
.Lpil_nil:
    adrp x0, _rail_nil@PAGE
    add x0, x0, _rail_nil@PAGEOFF
    ldp x29, x30, [sp], #32
    ret

//@ cat rgpumap, rparselist
