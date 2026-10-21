# runtime/arm64: the runtime every native Rail program links

Hand-written ARM64 assembly (Apple `as` syntax): equality and show, lists, strings, file and
process I/O, fibers and threads, float arrays, `try`, the libc replacements in `syscall.s`, the
collector (`gc_1.s` to `gc_5.s`), the arena and the data section (`data.s`: format strings, the
heap pointers, the young generation). One file per `rt_*` constant the compiler appends to
every program it builds. The Linux ARM64 cross-compile takes the same text, strips
the Darwin-specific stubs and links `tools/linux_libc.s` in their place. The x86_64 runtime is
`tools/x86_rt.s`, read at compile time; it is not here.

Until 2026-10-21 these files were 22 string constants inside `tools/compile.rail` (the 21 code
files at lines 4546 to 5050 of master `470cde9`, 110 KB, 18% of the file; the data section at
5189 of `589c117`).

## How it reaches a binary

1. `./rail_native run tools/gen_runtime.rail` reads every file named in its `rt_units` list and
   writes `tools/runtime_arm64.rail` (the 21 code files) and `tools/runtime_arm64_data.rail`
   (`data.s`): the same constants as Rail string literals. Both files are generated and
   committed; do not edit them.
2. `tools/compile.rail` imports each where its constants used to be written, and `runtime_asm`
   there joins the code files in the order a program carries them. The data section is its own
   module because the compiler emits string data in declaration order and the seed depends on
   it: `rt_data` must be declared 640 lines after the code, where `data_section_asm` was.
   Moving it up changed the seed (measured 2026-10-21); renaming it did not.
3. The compiler holds the text as data and appends it to every program it compiles. So a
   compiler emits the runtime it was **built** with: after an edit, a program carries the new
   runtime only once a compiler built from the new text compiles it.

## The format

Each file is assembly plus a few directives the generator reads:

| Line | Meaning |
|---|---|
| `//@ let NAME` | Starts a piece bound to `let NAME` in the constant. A file of lets ends with `//@ cat a, b, ...`, the order they are joined in (it differs from the file order in `core.s`, `closure.s` and `float.s`). |
| `//@ piece` | Starts an unnamed piece; the constant is `cat [piece, piece, ...]`. |
| `//@ literal` | The whole file is one string. |
| any other `//` line | Commentary. Not emitted. |
| anything else | Emitted as written, blank lines included. |

The three forms reproduce the declarations exactly as they were written in `compile.rail`, so
the move left the compiler byte-identical: built from this tree, the seed `cmp`s equal to the
seed built from the strings. A new file may use any form; `//@ literal` is the simplest.

## Changing the runtime

1. Edit the `.s` file.
2. `./rail_native run tools/gen_runtime.rail`
3. Bootstrap two cycles and a third for the fixed point (`docs/COMPILER_BOOTSTRAP.md`):
   `RAIL_ARENA_MB=6000 ./rail_native self`, install, again, then `cmp`.

A new file also needs its name in `rt_units` (`tools/gen_runtime.rail`, declaration order) and
`rt_<name>` in `runtime_asm` (`tools/compile.rail`, emit order). A `.s` file here that is not
in `rt_units` fails the generator.

CI runs `./rail_native run tools/gen_runtime.rail check`, which exits 1 when either generated
module is not what these files say: an edit here without step 2, or an
edit to the generated file by hand.
