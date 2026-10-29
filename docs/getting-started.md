# Getting Started with Rail

Rail is a self-hosting programming language that compiles to native ARM64 binaries. The compiler
is written in Rail itself and produces byte-identical output when compiling itself: a fixed
point. The measured size of the compiler and of the seed binary are rows of
[`STATUS.md`](STATUS.md), regenerated from the tree and compared in CI.

## Requirements

- Apple Silicon Mac (ARM64 macOS)

That is the whole list. Rail assembles, links and code-signs its own binaries in process: no
`as`, no `ld`, no `codesign`, no Xcode toolchain, no package manager, no runtime, no C.

## Install

```bash
git clone https://github.com/Ledatic-Empire/rail
cd rail
```

That is it. The seed binary `rail_native` is checked into the repo.

## Hello World

Create a file called `hello.rail`:

```rail
main =
  let _ = print "hello, world"
  0
```

Compile and run it:

```bash
./rail_native run hello.rail
```

Output:

```
hello, world
```

## How Compilation Works

Rail has two modes:

```bash
./rail_native hello.rail          # compile only -> /tmp/rail_out
./rail_native run hello.rail      # compile + execute
```

When you run `./rail_native hello.rail`, the compiler:

1. Reads `hello.rail` and tokenizes it
2. Parses tokens into a typed syntax tree
3. Infers types (Hindley-Milner; the types decide how values are represented) and checks that
   every `match` is exhaustive and every call passes the arguments its function declares
4. Generates ARM64 assembly
5. Assembles, links and ad-hoc code-signs it into a Mach-O binary, in process, in pure Rail
6. Writes the binary to `/tmp/rail_out` (or to the path given by `--out-prefix`)

With `run`, it then executes the binary. Two compiles running at once should each use their own
`--out-prefix`.

A quoted import such as `import "stdlib/float_hex.rail"` is read relative to the current
directory, so run the compiler from the repo root or give an absolute path (a bare
`import float_hex` also searches the compiler's own `stdlib/`). An import that is not found is
reported as a warning, and the program then fails at load; see the known limitations in
`CLAUDE.md`.

## A Slightly Bigger Program

```rail
double x = x * 2
factorial n = if n <= 1 then 1 else n * factorial (n - 1)

main =
  let _ = print "hello, rail"
  let _ = print (factorial 10)
  let _ = print (double 21)
  0
```

Output:

```
hello, rail
3628800
42
```

Key things to note:

- Functions are defined **before** `main`
- `main` must exist and must return an integer (the exit code)
- Side effects use `let _ = ...` to discard the result
- `print` outputs a value followed by a newline
- `show` converts a value to a string (not needed when printing ints directly)

## Running the Test Suite

```bash
./rail_native test
```

The suite runs inside the compiler binary and covers integers, strings, lists, tuples, ADTs,
closures, FFI, concurrency, the numerics contract and the crypto. The last line is
`N/N tests passed` and the exit status is 0 only when every case passed; the count is measured
by that line, never quoted here (`tests/README.md` explains how it is judged). About 80 s on
an M4 Pro.

## Self-Compilation

Rail compiles itself. To verify:

```bash
RAIL_ARENA_MB=6000 ./rail_native self
cmp rail_native /tmp/rail_self          # silent: the committed seed is what its source builds
```

This compiles `tools/compile.rail` (the compiler source) into `/tmp/rail_self`, byte-identical
to `rail_native` itself. `RAIL_ARENA_MB` sets where the first collection happens; the compiler's
own source needs at least 2000, and the output is the same at any value from there up.

## Rebuilding from Source

If you modify the compiler (`tools/compile.rail`):

```bash
# Step 1: compile with the old binary
RAIL_ARENA_MB=6000 ./rail_native self

# Step 2: install the new binary
cp /tmp/rail_self ./rail_native

# Step 3: compile with the new binary
RAIL_ARENA_MB=6000 ./rail_native self

# Step 4: verify the fixed point (silent when identical)
cmp rail_native /tmp/rail_self

# Step 5: if not identical, repeat steps 2 to 4 until stable (two cycles land it)

# Step 6: run the tests
./rail_native test    # every case: N/N tests passed, exit 0

# Step 7: regenerate the status matrix, which names the seed's bytes and hash
./rail_native run tools/verify/gen_status.rail
```

`docs/COMPILER_TOUR.md` walks the compiler in file order; `docs/COMPILER_BOOTSTRAP.md` has the
cycle rules and the traps.

## Other Commands

```bash
./rail_native quick               # the 15-case smoke subset
./rail_native types hello.rail    # the type checker's report
./rail_native asm hello.rail      # the assembly, written out
./rail_native x86 hello.rail      # cross-compile to Linux x86_64 assembly (/tmp/rail_x86.s)
./rail_native linux hello.rail    # cross-compile to a Linux ARM64 ELF (/tmp/rail_linux)
./rail_native run tools/repl.rail # a REPL with persistent definitions
./rail_native get json            # install a stdlib package into ~/.rail/packages
./rail_native packages            # list installed packages
```

## Project Structure

```
rail/
  rail_native           # seed binary (ARM64; bytes and hash in docs/STATUS.md)
  tools/
    compile.rail        # the compiler (one file; line count in docs/STATUS.md)
    types.rail          # type inference
    ast.rail            # the typed syntax tree
    v5/                 # the assembler, the Mach-O and ELF linkers, the signer
    verify/             # the check-me kit: status matrix, tour gate, examples gate, numerics vs C
  runtime/arm64/        # the runtime and the collector, as assembly
  stdlib/               # the standard library (module count in docs/STATUS.md)
  examples/             # example programs, each with its expected output in examples/expected/
  docs/                 # documentation (you are here)
```

## Next Steps

- [Language Reference](language-reference.md): complete syntax guide
- [Builtins](builtins.md): every built-in function
- [Standard Library](stdlib.md): the stdlib modules
- [Examples](examples.md): annotated example programs
- [Numerics](NUMERICS.md): what a Rail program's numbers are, sentence by sentence, each with its test
- [Check Rail yourself](../VERIFY.md): every claim as a command
