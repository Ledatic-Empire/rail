; tools/test/link_branch_comment.s: a one-operand branch with a trailing comment (t277, 2026-11-04).
; Until the fix the blanks before `//` stayed on the label, the lookup missed, and the b.le was
; emitted as a branch to itself: the function hung. Returns the number of elements of the n int64s
; at x0 that are at most the first one, counting the first (the lowbit argmax helper's shape).
.text
.p2align 2
_count_le_first:
    ldr x2, [x0]
    mov x3, #0
    mov x4, #0
.Lloop:
    cmp x4, x1
    b.ge .Ldone            // every element seen
    lsl x5, x4, #3
    add x5, x0, x5
    ldr x6, [x5]
    cmp x6, x2
    b.le .Lcount           // at most the first: count it
    add x4, x4, #1
    b .Lloop
.Lcount:
    add x3, x3, #1
    add x4, x4, #1
    cbz x1, .Ldone         // (never taken: n > 0 here)
    b .Lloop
.Ldone:
    mov x0, x3
    ret
