# Part 2: Allocators and Arguments

If you use a language with a Garbage Collector, you aren't a programmer; you're a tenant in a house you don't own. In Zig, we manage our own memory. This isn't just about efficiency; it's about correctness.

## The Power of Allocators

In `src/main.zig`, the first thing we do is set up the `GeneralPurposeAllocator` (GPA).

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

The `defer _ = gpa.deinit();` is the most important line in the program. When the server shuts down, the GPA will check if we leaked any memory. If we did, it tells us exactly where. This forces you to write clean code.

## Manual CLI Parsing

Most devs pull in a 50kb library to parse three flags. We don't do that. We use `std.process.argsWithAllocator` to get an iterator over the command line arguments.

In `src/options.zig`, we loop through these arguments manually:

```zig
while (args.next()) |arg| {
    if (std.mem.eql(u8, arg, "-listen")) {
        // ... parse addr:port ...
    } else if (std.mem.eql(u8, arg, "-port")) {
        // Explicitly override the port
        if (args.next()) |val| options.listen_port = try std.fmt.parseInt(u16, val, 10);
    } else if (std.mem.eql(u8, arg, "-file")) {
        // Provide a fallback file for directory requests
        options.fallback_file = args.next();
    } else if (std.mem.eql(u8, arg, "-sandbox")) {
        options.sandbox = true;
    }
}
```

### The Zig 0.15 ArrayList Pattern

Note how we handle the `headers` list. In older Zig versions, the list stored the allocator. In Zig 0.15, we follow the "Unmanaged" style even in the managed `ArrayList` for consistency across the standard library.

```zig
// In the Options struct
headers: std.ArrayList(HttpHeader),
allocator: std.mem.Allocator,

// When adding a header
try options.headers.append(options.allocator, .{ .name = name, .value = value });

// When cleaning up
pub fn deinit(self: *Options) void {
    self.headers.deinit(self.allocator);
}
```

This ensures that the `Options` struct doesn't have a hidden dependency on where its memory came from until it actually needs to perform an operation. It makes the data structure "inert" and easier to move between threads.
