# fibonacci — recursion, range, map

A naive recursive Fibonacci, then mapped across `range 16`.

**Source** (`examples/fibonacci.rail`):

```rail
-- fibonacci.rail — recursive Fibonacci sequence
--
-- Demonstrates: recursion, if/then/else, show, range, map

fib n = if n <= 1 then n else fib (n - 1) + fib (n - 2)

showNum x = show x

fibOf x = fib x

main =
  let _ = print "Fibonacci sequence (0-15):"
  let nums = range 16
  let fibs = map fibOf nums
  let _ = print (join " " (map showNum fibs))
  let _ = print ""
  let _ = print (append "fib(30) = " (show (fib 30)))
  0
```

**Run:**

```bash
./rail_native run examples/fibonacci.rail
```

**Output:**

```
Compiling examples/fibonacci.rail (433 chars)...
  as: OK
  ld: OK
Fibonacci sequence (0-15):
0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610

fib(30) = 832040
```

The output above is a real run on master (2026-10-19). An earlier version of this page showed a miscompiled run, negative numbers and all, and explained them as overflow; `fib 30` is 832040 and fits easily in Rail's 63-bit integers.
