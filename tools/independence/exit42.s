; tools/independence/exit42.s: the smallest program that walks every region of the seed
; format (docs/SEED_FORMAT.md): __text with an inline string and alignment padding, one
; libSystem import (a stub, a GOT slot, a bind), a @PAGE pair into __data and one into
; __bss, a __data pointer into __text and one into __data (two rebases), the module
; initialiser the linker always writes, and the signature over all of it. The process
; stores 42 and exits with it. tools/independence/seed_writer.py builds the same file
; from the document alone; tools/independence/seed_format_gate.sh cmp's the two.
.section __TEXT,__text
.global _main
.p2align 2
_rail_arena_init:
    ret
_main:
    adrp x1, _answer@PAGE
    add x1, x1, _answer@PAGEOFF
    ldr x0, [x1]
    adrp x2, _slot@PAGE
    add x2, x2, _slot@PAGEOFF
    str x0, [x2]
    adr x3, .Lmsg
    bl _exit
    ret
.Lmsg:
    .asciz "exit42"
.p2align 2
.section __DATA,__data
.p2align 3
_answer:
    .quad 42
_entry:
    .quad _main
_name:
    .quad .Lmsg
.zerofill __DATA,__bss,_slot,8,3
.section __DATA,__mod_init_func,mod_init_funcs
.p2align 3
.quad _rail_arena_init
