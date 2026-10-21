// runtime/arm64/data.s: the runtime's data section, appended after the code of every program.
//
// Format strings for printf and snprintf (_fmt_int "%ld\n", _fmt_str "%s\n", _fmt_ld "%ld"),
// the arena's heap pointers, argc/argv/envp, the try handler stack top (one global across
// threads, issue #116 item 3), and the young generation: two 64 MB semi-spaces in bss whose
// pointer state ships as linker-initialized data (scaffolding; the allocator still bumps
// _rail_heap_ptr). The mod_init entry runs _rail_arena_init before main.
//
// Until 2026-10-21 this was the constant data_section_asm in tools/compile.rail. It is carried
// by tools/runtime_arm64_data.rail, imported later in compile.rail than the other files, because
// declaration order fixes the seed (runtime/arm64/README.md).
//@ literal

.section __DATA,__data
_fmt_int:
    .byte 37, 108, 100, 10, 0
_fmt_str:
    .byte 37, 115, 10, 0
_fmt_ld:
    .byte 37, 108, 100, 0
_fmt_g:
    .asciz "%g\n"
_fmt_gbare:
    .asciz "%.15g"
_fmt_g17:
    .asciz "%.17g"
.p2align 3
_rail_empty_str:
    .byte 0
_mode_w:
    .asciz "w"
_mode_r:
    .asciz "r"
_rail_arena_env_name:
    .asciz "RAIL_ARENA_MB"
_rail_arena_trace_env:
    .asciz "RAIL_ARENA_TRACE"
_rail_gc_stress_env:
    .asciz "RAIL_GC_STRESS"
.p2align 3
_rail_nil:
    .quad 2
.p2align 3
.global _rail_heap_ptr
_rail_heap_ptr:
    .quad 0
.p2align 3
.global _rail_heap_end
_rail_heap_end:
    .quad 0
.p2align 3
.global _rail_heap_limit
_rail_heap_limit:
    .quad 0
.p2align 3
.global _rail_heap_base
_rail_heap_base:
    .quad 0
.p2align 3
_rail_argc:
    .quad 0
_rail_argv:
    .quad 0
_rail_envp:
    .quad 0
.p2align 3
_rail_handler_top:
    .quad 0
.p2align 3
.global _rail_young_base
_rail_young_base:
    .quad _rail_young_a
.p2align 3
.global _rail_young_end
_rail_young_end:
    .quad _rail_young_a + 67108864
.p2align 3
.global _rail_young_ptr
_rail_young_ptr:
    .quad _rail_young_a
.p2align 3
.global _rail_young_to_base
_rail_young_to_base:
    .quad _rail_young_b
.p2align 3
.global _rail_young_to_end
_rail_young_to_end:
    .quad _rail_young_b + 67108864
.global _rail_young_a
.zerofill __DATA,__bss,_rail_young_a,67108864,3
.global _rail_young_b
.zerofill __DATA,__bss,_rail_young_b,67108864,3
.section __DATA,__mod_init_func,mod_init_funcs
.p2align 3
.quad _rail_arena_init
