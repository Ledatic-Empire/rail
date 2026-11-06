; tools/test/link_add3.s: the assembly a program carries with `link "tools/test/link_add3.s"`
; (t274). Three untagged ints in, their sum out; the FFI retags the result. Comments are `;`
; (Rail's assembler); `//` is for runtime/arm64 files, whose generator strips it.
.text
.p2align 2
_add3:
    add x0, x0, x1
    add x0, x0, x2
    ret
