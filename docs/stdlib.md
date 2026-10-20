# Rail Standard Library

81 modules in `stdlib/` (`ls stdlib/*.rail`). This page documents the core set; every module is import-able the same way:

```rail
import "stdlib/<module>.rail"
```

Or with a qualifier:

```rail
import "stdlib/<module>.rail" as M
```

---

## base64

**Pure Rail Base64 encode/decode.** Uses `shell` calls for character code conversion (ASCII only).

```rail
import "stdlib/base64.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `base64_encode` | `string -> string` | Encode a string to Base64. |
| `base64_decode` | `string -> string` | Decode a Base64 string. |

### Example

```rail
import "stdlib/base64.rail"

main =
  let encoded = base64_encode "hello, world"
  let _ = print encoded
  let decoded = base64_decode encoded
  let _ = print decoded
  0
```

---

## env

**Environment variables via FFI.** Wraps `getenv`/`setenv`.

```rail
import "stdlib/env.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `get_env` | `name -> string` | Get environment variable value. Returns empty string if not set. |
| `set_env` | `name value -> int` | Set environment variable. |

### Example

```rail
import "stdlib/env.rail"

main =
  let home = get_env "HOME"
  let _ = print (cat ["Home: ", home])
  0
```

---

## file

**File I/O via FFI.** Wraps `fopen`/`fclose`/`fread`/`fwrite`/`fseek`/`ftell`, plus convenience wrappers around the builtins.

```rail
import "stdlib/file.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `open_read` | `path -> ptr` | Open file for reading. Returns 0 on failure. |
| `open_write` | `path -> ptr` | Open file for writing. |
| `open_append` | `path -> ptr` | Open file for appending. |
| `close` | `fp -> int` | Close a file pointer. |
| `slurp` | `path -> string` | Read entire file contents (wraps `read_file`). |
| `spit` | `path content -> int` | Write string to file (wraps `write_file`). |

### Low-Level FFI

Also exports: `fopen`, `fclose`, `fread`, `fwrite`, `fseek`, `ftell`.

---

## hash

**Pure Rail hash functions.** FNV-1a 32-bit hash with a simple hash table implementation.

```rail
import "stdlib/hash.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `hash_string` | `string -> int` | FNV-1a 32-bit hash of a string. |
| `hash_int` | `int -> int` | Hash an integer (converts to string first). |
| `ht_new` | `_ -> hashtable` | Create a new hash table (64 buckets). |
| `ht_put` | `ht key value -> hashtable` | Insert/update a key-value pair. |
| `ht_get` | `ht key -> string` | Look up a value by key. Returns "" if not found. |

### Example

```rail
import "stdlib/hash.rail"

main =
  let ht = ht_new 0
  let ht = ht_put ht "name" "Rail"
  let ht = ht_put ht "version" "1.4.0"
  let _ = print (ht_get ht "name")
  0
```

---

## json

**Pure Rail JSON parser.** Parses JSON into a tagged list representation, with accessors and serialization.

```rail
import "stdlib/json.rail"
```

### Representation

JSON values are represented as tagged lists:

| JSON | Rail representation |
|------|-------------------|
| `"hello"` | `["str", "hello"]` |
| `42` | `["num", 42]` |
| `true` | `["bool", true]` |
| `null` | `["null"]` |
| `[1, 2]` | `["arr", [["num", 1], ["num", 2]]]` |
| `{"k": "v"}` | `["obj", [("k", ["str", "v"])]]` |

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `parse_json` | `string -> json_value` | Parse a JSON string into a Rail value. |
| `json_get` | `obj key -> json_value` | Get a value from a JSON object by key. |
| `json_str` | `json_value -> string` | Extract a string value (returns "" for non-strings). |
| `json_int` | `json_value -> int` | Extract an integer value (returns 0 for non-numbers). |
| `json_items` | `json_value -> [json_value]` | Extract array items (returns [] for non-arrays). |
| `json_encode` | `json_value -> string` | Serialize a JSON value back to a string. |

### Example

```rail
import "stdlib/json.rail"

main =
  let data = parse_json "{\"name\": \"Rail\", \"version\": 140}"
  let name = json_str (json_get data "name")
  let ver = json_int (json_get data "version")
  let _ = print (cat [name, " v", show ver])
  0
```

---

## list

**List utilities.** Higher-order functions and common operations not in the builtins.

```rail
import "stdlib/list.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `sum` | `[int] -> int` | Sum all elements. |
| `product` | `[int] -> int` | Product of all elements. |
| `take` | `n xs -> [a]` | Take first n elements. |
| `drop` | `n xs -> [a]` | Drop first n elements. |
| `zip` | `xs ys -> [(a, b)]` | Zip two lists into pairs. |
| `nth` | `n xs -> a` | Get nth element (0-indexed). |
| `any` | `pred xs -> bool` | True if any element satisfies predicate. |
| `all` | `pred xs -> bool` | True if all elements satisfy predicate. |
| `flatten` | `[[a]] -> [a]` | Flatten a list of lists. |
| `mapi` | `f xs -> [b]` | Map with index: `f index element`. |
| `sort` | `[int] -> [int]` | Insertion sort (ascending). |

### Example

```rail
import "stdlib/list.rail"

main =
  let _ = print (show (sum [1, 2, 3, 4, 5]))
  let pairs = zip [1, 2, 3] ["a", "b", "c"]
  let first3 = take 3 (range 10)
  let _ = print (show (nth 2 first3))
  0
```

---

## math

**Math functions via FFI to libm.** All trig/exponential functions take and return floats.

```rail
import "stdlib/math.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `sin` | `float -> float` | Sine. |
| `cos` | `float -> float` | Cosine. |
| `sqrt` | `float -> float` | Square root. |
| `pow` | `float float -> float` | Power. |
| `log` | `float -> float` | Natural logarithm. |
| `exp` | `float -> float` | e^x. |
| `floor` | `float -> float` | Floor. |
| `ceil` | `float -> float` | Ceiling. |
| `fabs` | `float -> float` | Absolute value (float). |
| `atan2` | `float float -> float` | Two-argument arctangent. |
| `abs_int` | `int -> int` | Absolute value (integer). |
| `min` | `int int -> int` | Minimum. |
| `max` | `int int -> int` | Maximum. |
| `clamp` | `lo hi x -> int` | Clamp x to [lo, hi]. |

### Constants

- `pi` -- computed via `atan2(0, -1)`
- `e` -- computed via `exp(1)`

### Example

```rail
import "stdlib/math.rail"

main =
  let _ = print (show (sqrt (to_float 144)))
  let _ = print (show (abs_int (-42)))
  let _ = print (show (clamp 0 100 150))
  0
```

---

## mmap

**Memory-mapped I/O via FFI.** Wraps `mmap`/`munmap` from libSystem.

```rail
import "stdlib/mmap.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `alloc_pages` | `len -> ptr` | Allocate anonymous memory pages (MAP_PRIVATE + MAP_ANON). |
| `free_pages` | `addr len -> int` | Unmap memory. |

### Constants

- `prot_none`, `prot_read`, `prot_write`, `prot_exec`, `prot_rw`
- `map_shared`, `map_private`, `map_anon`

---

## socket

**BSD sockets via FFI.** Low-level socket operations.

```rail
import "stdlib/socket.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `tcp_socket` | `_ -> int` | Create a TCP socket (AF_INET, SOCK_STREAM). |
| `udp_socket` | `_ -> int` | Create a UDP socket (AF_INET, SOCK_DGRAM). |
| `close_socket` | `fd -> int` | Close a socket. |

### Low-Level FFI

Also exports: `socket`, `bind`, `listen`, `accept`, `connect`, `send`, `recv`, `close`, `htons`.

### Constants

- `af_inet` = 2
- `sock_stream` = 1
- `sock_dgram` = 2

---

## sqlite

**SQLite3 via FFI.** Requires `-lsqlite3` to be added to the linker command manually.

```rail
import "stdlib/sqlite.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `exec` | `db sql -> int` | Execute SQL statement. Returns 0 on success. |
| `close_db` | `db -> int` | Close database. |

### Low-Level FFI

Also exports: `sqlite3_open`, `sqlite3_exec`, `sqlite3_close`.

### Constants

- `sqlite_ok` = 0
- `sqlite_error` = 1
- `sqlite_busy` = 5

**Note**: Currently requires manually adding `-lsqlite3` to the linker flags.

---

## stat

**File metadata via FFI.** Uses `access()` for permission checks and `shell` for size/mtime.

```rail
import "stdlib/stat.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `file_exists` | `path -> bool` | Check if file exists. |
| `is_readable` | `path -> bool` | Check if file is readable. |
| `is_writable` | `path -> bool` | Check if file is writable. |
| `file_size` | `path -> int` | Get file size in bytes. Returns -1 on failure. |
| `file_mtime` | `path -> int` | Get modification time as Unix timestamp. |

### Example

```rail
import "stdlib/stat.rail"

main =
  if file_exists "/tmp/data.txt" then
    let size = file_size "/tmp/data.txt"
    let _ = print (cat ["Size: ", show size, " bytes"])
    0
  else
    let _ = print "File not found"
    0
```

---

## string

**String utilities.** Common operations not in the builtins.

```rail
import "stdlib/string.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `starts_with` | `prefix s -> bool` | Check if string starts with prefix. |
| `contains_char` | `c s -> bool` | Check if string contains a character. |
| `repeat_str` | `s n -> string` | Repeat string n times. |
| `pad_right` | `s width -> string` | Right-pad with spaces to width. |
| `pad_left` | `s width -> string` | Left-pad with spaces to width. |
| `cat` | `[string] -> string` | Concatenate list of strings (alias for `join ""`). |
| `intercalate` | `sep xs -> string` | Join with separator (alias for `join`). |
| `from_chars` | `[string] -> string` | Convert list of single-char strings back to a string. |

---

## time

**Time functions via FFI.** Unix timestamp and sleep.

```rail
import "stdlib/time.rail"
```

### Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `now` | `_ -> int` | Get current Unix timestamp (seconds since epoch). |
| `wait` | `n -> int` | Sleep for n seconds. |

### Example

```rail
import "stdlib/time.rail"

main =
  let t = now 0
  let _ = print (cat ["Timestamp: ", show t])
  0
```

---
