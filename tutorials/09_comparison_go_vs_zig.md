# Part 9: The Battle - Go vs. Zig Architectural Side-by-Side

Let's look at the actual code transformations that happened during this rewrite. This is how you move from a high-level language to a system language.

## 1. Concurrency

### Go (Goroutines)
```go
go t.handleConnection(c, t.HandleMessageFnc)
```
In Go, you just throw the `go` keyword at a function. It's easy, but you lose control. The scheduler decides when it runs.

### Zig (System Threads)
```zig
_ = try std.Thread.spawn(.{}, handleConnection, .{ allocator, options, conn });
```
In Zig, we explicitly spawn an OS thread. We pass the `allocator` because the thread needs memory for its own context. We see the `try` because spawning a thread can fail (e.g., out of memory).

## 2. Error Handling

### Go (The `if err != nil` Loop)
```go
f, err := sbfs.fs.Open(path)
if err != nil {
    return nil, err
}
```
Go uses tuples for errors. It's manual, but the errors are just values.

### Zig (Error Sets and `try`)
```zig
const file = try std.fs.cwd().openFile(full_path, .{});
```
Zig uses a dedicated Error Set type. The `try` keyword is syntax sugar for:
```zig
const file = std.fs.cwd().openFile(full_path, .{}) catch |err| return err;
```
It's more concise but keeps the error path explicit.

## 3. The Filesystem

### Go (`http.FileSystem`)
Go uses an interface for the filesystem. It's flexible but relies on dynamic dispatch (vtables) everywhere.

### Zig (`std.fs.Dir`)
Zig uses a struct that maps directly to the OS file descriptors. We call `realpathAlloc` to get the absolute path, which is a direct syscall on Linux. We aren't working through a "filesystem abstraction layer"; we are talking to the kernel.

## 4. Binary Size

- **Go version:** ~10MB (includes runtime, GC, debug symbols).
- **Zig version (Static):** ~450KB.

That's a **95% reduction in bloat.** That is the "Suckless" tax.
