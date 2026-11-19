# Rail Builtins Reference

Every built-in function available without importing any module. These are compiled directly into the generated ARM64 assembly.

## I/O

### `print`

Print a value to stdout followed by a newline.

```rail
print "hello"           -- prints: hello
print 42                -- prints: 42
print (show (3 + 4))    -- prints: 7
```

Integers are printed as decimal numbers. Strings are printed as-is. For other types, use `show` first.

### `show`

Convert a tagged integer to its string representation.

```rail
show 42      -- returns "42"
show (-7)    -- returns "-7"
show 0       -- returns "0"
```

Also works on floats:

```rail
show 3.14    -- returns "3.14"
show (1.5 + 2.25)  -- returns "3.75"
```

### `read_file`

Read the entire contents of a file as a string. Returns an empty string if the file does not exist.

```rail
let content = read_file "/tmp/data.txt"
```

### `write_file`

Write a string to a file, creating it if it does not exist, overwriting if it does. Returns 0
when the file was written. When the file cannot be opened (a missing directory, no permission)
it prints `rail: write_file: cannot open <path>` on standard error and returns 1 (since
2026-10-30; it returned 0 either way before). The string is written up to its first NUL byte.

```rail
let r = write_file "/tmp/output.txt" "hello, world"   -- 0 when written, 1 when not
```

### `shell`

Execute a shell command and return its stdout as a string.

```rail
let date = shell "date +%Y-%m-%d"
let files = shell "ls -1 /tmp"
```

The entire stdout output is returned, including trailing newlines. Use `trim` or `split` to clean it up:

```rail
let date = head (split "\n" (shell "date"))
```

### `cat`

Concatenate a list of strings into one string (equivalent to `join "" list`).

```rail
cat ["hello", " ", "world"]    -- returns "hello world"
cat [show 1, "+", show 2]      -- returns "1+2"
```

## Lists

### `head`

Return the first element of a list.

```rail
head [10, 20, 30]    -- returns 10
head ["a", "b"]      -- returns "a"
```

Calling `head` on an empty list returns `0`. (Rail runtime safety: both `head []` and `head` on a non-list return `0` rather than segfaulting.)

### `tail`

Return all elements except the first.

```rail
tail [10, 20, 30]    -- returns [20, 30]
tail [1]             -- returns []
tail []              -- returns [] (tail on a non-list also returns [])
```

### `cons`

Prepend an element to a list.

```rail
cons 1 [2, 3]        -- returns [1, 2, 3]
cons "a" []          -- returns ["a"]
```

### `append`

Concatenate two lists, or concatenate two strings.

```rail
append [1, 2] [3, 4]     -- returns [1, 2, 3, 4]
append "hello" " world"  -- returns "hello world"
```

The `+` operator on strings also calls `append`:

```rail
"foo" + "bar"    -- returns "foobar"
```

### `length`

Return the number of elements in a list, or the number of bytes in a string (`length "héllo"`
is 6: the text is UTF-8 and `é` is two bytes).

```rail
length [1, 2, 3]     -- returns 3
length []            -- returns 0
length "hello"       -- returns 5
```

### `map`

Apply a function to every element of a list.

```rail
double x = x * 2
map double [3, 5, 7]           -- returns [6, 10, 14]
map (\x -> x + 10) [1, 2, 3]  -- returns [11, 12, 13]
```

Lambdas work correctly with `map`.

### `filter`

Keep only elements that satisfy a predicate.

```rail
gt2 x = if x > 2 then true else false
filter gt2 [1, 2, 3, 4, 5]    -- returns [3, 4, 5]
```

Inline lambdas work in `filter`, including ones that capture outer values:

```rail
filter (\x -> x > 2) [1, 2, 3, 4, 5]    -- returns [3, 4, 5]

let lo = 2
filter (\x -> x > lo) [1, 2, 3, 4, 5]   -- captures `lo`; returns [3, 4, 5]
```

Named predicate functions read more clearly for anything non-trivial.

### `fold`

Left fold over a list with an accumulator.

```rail
add a b = a + b
fold add 0 [1, 2, 3, 4, 5]    -- returns 15
```

`fold f init [a, b, c]` computes `f (f (f init a) b) c`.

Multi-argument lambdas work directly:

```rail
fold (\a b -> a + b) 0 [1, 2, 3, 4, 5]    -- returns 15
```

Named 2-argument functions are equally fine.

### `reverse`

Reverse a list.

```rail
reverse [1, 2, 3]    -- returns [3, 2, 1]
```

### `join`

Join a list of strings with a separator.

```rail
join "-" ["a", "b", "c"]    -- returns "a-b-c"
join ", " ["one", "two"]    -- returns "one, two"
join "" ["hello", "world"]  -- returns "helloworld"
```

### `range`

Generate a list of integers from 0 to N-1.

```rail
range 5     -- returns [0, 1, 2, 3, 4]
range 0     -- returns []
range 1     -- returns [0]
```

## Strings

### `chars`

Split a string into a list of single-character strings.

```rail
chars "abc"    -- returns ["a", "b", "c"]
chars ""       -- returns []
```

### `split`

Split a string by delimiter characters.

```rail
split "," "a,b,c"          -- returns ["a", "b", "c"]
split " " "hello world"    -- returns ["hello", "world"]
split "\n" "line1\nline2"  -- returns ["line1", "line2"]
```

**Important**: `split` takes a *single-character* delimiter. If you pass a multi-character string, only the **first** character is used; it is not a set of delimiters, and not a substring:

```rail
split "ab" "xaybz"    -- uses only "a" -> ["x", "ybz"]   ("b" is NOT a delimiter)
```

This is the most common gotcha in Rail. For multi-character (substring) delimiters, use `str_split`.

### `append` (strings)

Concatenate two strings:

```rail
append "hello" " world"    -- returns "hello world"
```

Also available via the `+` operator on strings.

### `trim`

Remove trailing newlines from a string (returns text up to the first newline).

```rail
trim "hello\nworld"    -- returns "hello"
```

Note: `trim` in the compiler is defined as `head (split "\n" s)`, so it really just returns the first line.

## Names, errors, arrays and string edges

### Builtin names are reserved

A top-level definition whose name is a builtin's (`range a b = ...`) is a compile error. Until
2026-11-18 it compiled and every call still reached the builtin. The one exception is the
`cat` helper many programs carry (`cat xs = join "" xs`), which is the builtin's own meaning.

### `error`, `is_error`, `err_msg`, `try`

`error "msg"` makes an error value. Outside `try` it does not stop the program at once: the
value is returned like any other and execution goes on. `is_error v` tells it from an ordinary
value and `err_msg v` gives its message. Inside `try (\_ -> body) (\e -> handler)` an `error`
leaves the body and the handler runs.

An error nobody looked at is reported when `main` returns: the program prints
`rail: unhandled error: <msg>` on stderr and exits 1 (since 2026-11-19; before, it exited 0
in silence). Looking at it means `is_error`, `err_msg` or a `try` around it. When several were
raised, the last one not looked at is named.

```rail
let e = error "oops"
is_error e                                   -- true; the next line still runs
err_msg e                                    -- "oops"
try (\_ -> error "boom") (\e -> 0 - 1)       -- -1
```

### Arrays

`arr_new n v`, `arr_get a i`, `arr_set a i v`, `arr_len a`. An index outside
`0 .. arr_len a - 1` in `arr_get` or `arr_set`, and a negative length to `arr_new`, end the
program with a message on stderr and exit code 1 (`rail: array index out of bounds`,
`rail: arr_new: negative length`). Float arrays are checked the same way since 2026-11-19.
The x86_64 backend emits the same checks; they are assembled on every CI run and executed
only by CI's `numerics-x86` job.

### Float arrays

`float_arr_new n v` makes an array of n doubles, each v. `float_arr_get a i`,
`float_arr_set a i v`, `float_arr_len a`.

```rail
let a = float_arr_new 3 1.5
let _ = float_arr_set a 1 4.0
float_arr_len a        -- 3
float_arr_get a 1      -- 4.0
```

`float_arr_to_f32_file path a n` writes the first n elements as little-endian float32 (4n
bytes) and `float_arr_from_f32_file path a n` reads n float32 values into `a`. The path comes
first. Both return 1.

### `str_sub`, `str_replace`, `str_split`

`str_sub s start count` clamps to the string: a start past the end gives `""`, a count past
the end gives what is there, a negative start counts as 0. `str_replace old new s` with an
empty `old` returns `s`. `str_split delim s` with an empty `delim` returns `[s]`.

### Literal type errors

The compiler refuses the type errors it can see from a literal: arithmetic on a string, list,
tuple or lambda literal (`"a" - 1`), such a literal passed to a top-level function that does
arithmetic on that parameter, a call to a name bound to a literal (`let g = 5` then `g 3`),
and, since 2026-11-19, the same mistakes made through a name a `let` binds once to a literal
(`let s = "abc"` then `s - 1`). Anything that needs inference is not checked at compile time;
`rail types` reports more, and reports some working programs too, so it is advice.

### Argument counts

A call that gives a builtin or a top-level function more or fewer arguments than it takes is
a compile error (`'range' takes 1 argument(s), called with 2`). Builtins have been checked
since 2026-11-19: before, an extra argument was dropped (`range 1 8` was `range 1`) and a
missing one read whatever was in the register. The channel, fiber, `spawn`, `send` and `recv`
names are not checked, because programs also bind them as foreign functions of other arities.

### Integer range

Integers are 63-bit: -4611686018427387904 to 4611686018427387903. A literal outside that range
is a compile error. Arithmetic past it wraps without notice (`4611686018427387903 + 1` is
-4611686018427387904). Division and remainder by zero do not stop the program: `a / 0` is 0
and `a % 0` is `a` (measured on ARM64; the x86_64 backend has emitted the same answers since
2026-11-19, executed by CI only).

### Recursion depth

A call that is not a tail call uses the machine stack. A recursion deep enough to exhaust it
(tens of millions of frames on macOS) ends the program with `rail: stack overflow` on stderr
and exit code 1 (since 2026-11-19; before, a bare `Bus error: 10`). Write the loop as a tail
call (an accumulator) and it runs in constant stack.

### Bits and bytes

`bit_and a b`, `bit_or a b`, `bit_xor a b`. `shl x n` shifts left and `shr x n` shifts right
without sign extension, both on the 64-bit machine word with the result cut back to 63 bits:
`shl 1 62` is -4611686018427387904 and `shr (0 - 1) 60` is 15. `rotl x n` and `rotr x n`
rotate the 64-bit word, so a bit rotated past the top is lost to the tag (`rotr 1 1` is 0);
for 32-bit rotations mask and combine `shl` and `shr`. `mul_shr a b s` is `(a * b) >> s` with
the product kept exact in 128 bits (`mul_shr 6 7 1` is 21): the fixed-point multiply.

`byte_at s i` is the byte at offset i of a string or byte buffer, as an int;
`byte_set s i v` stores one. Neither checks i against the length: an offset past the end
reads or writes whatever is there. `char_to_int c` is the first byte of a string (0 for
`""`) and `char_from_int n` is the one-byte string for n.

```rail
bit_and 12 10          -- 8
bit_xor 12 10          -- 6
shl 1 10               -- 1024
byte_at "abc" 1        -- 98
char_from_int 98       -- "b"
```

### Searching and parsing strings

The needle comes first. `str_find needle s` is the byte offset of the first match or -1;
`str_contains needle s` is 1 or 0.

```rail
str_find "l" "hello"         -- 2
str_find "z" "hello"         -- -1
str_contains "ell" "hello"   -- 1
```

`parse_int s` reads a leading decimal integer and stops at the first other character:
`parse_int "12abc"` is 12 and `parse_int "abc"` is 0, with no error. `parse_float s` is the
correctly rounded double (the conversion the compiler uses for literals); `parse_float "abc"`
is 0.

### More I/O

`read_line 0` returns the next line of stdin without its newline, and `""` at end of input.
`read_file_bytes path` returns the file as a raw byte buffer for `byte_at`, zero bytes
included; it carries no length, so take the size from the format or from `shell "wc -c"`.

## Math

### `not`

Logical NOT. Flips a boolean value.

```rail
not true     -- returns false
not false    -- returns true
```

### `to_float`

Convert an integer to a float.

```rail
to_float 42       -- returns 42.0
to_float (-5)     -- returns -5.0
```

Required when calling math FFI functions like `sqrt`:

```rail
foreign sqrt x -> float
let result = sqrt (to_float 144)    -- returns 12.0
```

### `round32`, `fma32`, `f32_bits`

binary32 arithmetic on Rail's doubles (2026-10-29; `docs/NUMERICS.md` 19 to 21). `round32 x` is
x rounded to the nearest float32 and back; `fma32 a b c` is the float32 fused multiply-add of
the float32 values of a, b and c; `f32_bits x` is the float32 bit pattern as an int.

```rail
round32 0.1                 -- 0.10000000149011612 (3fb99999a0000000)
fma32 1.5 2.5 (round32 0.3) -- 4.050000190734863
f32_bits 1.0                -- 1065353216
```

### `to_int`, `float_to_int`, `int_to_float`

`to_int x` and `float_to_int x` convert a float to an integer, truncating toward zero.
`int_to_float n` is `to_float n`.

```rail
to_int 3.7     -- returns 3
to_int (-2.9)  -- returns -2
```

### `fabs`, `fneg`, `fsqrt`

Absolute value, negation and square root of a float, each one machine instruction.
(`fabs` did not link until 2026-11-19: the assembler had no encoding for it.)

```rail
fabs (0.0 -. 2.5)    -- 2.5
fneg 2.5             -- -2.5
fsqrt 9.0            -- 3.0
```

### `show_float`, `show_float_exact`

`show_float x` prints 15 significant digits (`show_float (1.0 /. 3.0)` is
`0.333333333333333`); `show_float_exact x` prints 17, enough to read the same double back
(`0.33333333333333331`; `show_float_exact 0.1` is `0.10000000000000001`).

## Memory

### `arena_mark`

Return the current heap pointer position as an opaque value.

```rail
let mark = arena_mark 0
```

The argument is ignored (pass 0).

### `arena_reset`

Reset the heap pointer to a previously saved position and clear the free list.

```rail
let mark = arena_mark 0
let _ = cons 1 [2, 3]     -- allocate some data
let _ = arena_reset mark   -- free everything since mark
```

**Warning**: All data allocated after the mark becomes invalid.

### `rc_alloc`

Allocate a reference-counted block of the given size in bytes.

```rail
let p = rc_alloc 128
```

### `rc_retain`

Increment the reference count of a block allocated with `rc_alloc`.

```rail
rc_retain p
```

### `rc_release`

Decrement the reference count. Frees the block when it reaches zero.

```rail
rc_release p
```

## Concurrency

### `spawn`

Spawn a fiber running a function. Returns a fiber handle.

```rail
let f = spawn (\x -> some_work x)
```

### `channel`

Create a new channel. The argument is ignored (pass 0).

```rail
let ch = channel 0
```

### `send`

Send a value to a channel.

```rail
send ch 42
```

### `recv`

Receive the next value from a channel.

```rail
let val = recv ch
```

### `fiber_init`

Initialize the fiber runtime. Call once before using spawn.

```rail
let _ = fiber_init
```

### `fiber_yield`

Yield the current fiber, allowing other fibers to run.

```rail
let _ = fiber_yield
```

### `fiber_await`

Wait for a spawned fiber to complete and return its result.

```rail
let result = fiber_await f
```

### `spawn_thread`, `join_thread`

`spawn_thread f x` runs `f x` on a new OS thread and returns a handle; `join_thread h` waits
for it and returns the result. The collector does not run while a thread is live.

```rail
let t = spawn_thread (\v -> v + 10) 5
join_thread t        -- 15
```

### `mutex_new`, `mutex_lock`, `mutex_unlock`

`mutex_new 0` makes a pthread mutex; `mutex_lock m` and `mutex_unlock m` take and release it
and return 0. (Until 2026-11-19 `mutex_new` returned 0 and the first lock crashed.)

### `alloc_stats_snapshot`

`alloc_stats_snapshot 0` returns an int array of the allocator's counters. A diagnostic for
work on the runtime; its layout is not a stable interface.

## System

### `args`

The command-line arguments as a list of strings. The first element is the program name.

```rail
main =
  let a = args
  let _ = print (show (length a))
  0
```

### `import`

Import declarations from another Rail source file:

```rail
import "stdlib/json.rail"
import "stdlib/math.rail" as M
```

See [Language Reference](language-reference.md#import-system) for details.
