# Part 4: The Fortress - Filesystem and Sandbox

Serving files over the internet is dangerous. If you just take a URL like `/../../etc/passwd` and append it to your root directory, you’re going to have a bad time. 

## The Sandbox Logic

The "Sandbox Mode" ensures that no matter what the user requests, we only ever serve files from the designated folder. We achieve this using path resolution.

In `src/http.zig`, we implement this check:

```zig
const full_path = try std.fs.path.join(allocator, &.{ options.folder, decoded_path });

if (options.sandbox) {
    // Resolve the path to its absolute, canonical form
    const resolved = std.fs.cwd().realpathAlloc(allocator, full_path) catch {
        try request.respond("Forbidden", .{ .status = .forbidden });
        return;
    };
    defer allocator.free(resolved);

    // Verify the resolved path still starts with our root folder
    if (!std.mem.startsWith(u8, resolved, options.folder)) {
        try request.respond("Forbidden", .{ .status = .forbidden });
        return;
    }
}
```

By resolving the path *before* checking the prefix, we automatically handle `..`, symlinks, and multiple slashes. If the resolved path isn't a sub-path of our root, we kill the request.

## Directory Iteration

When a user requests a folder, we need to show them what’s inside. We use `dir.iterate()` to get an iterator that doesn't allocate for every entry.

```zig
var iter = dir.iterate();
while (try iter.next()) |entry| {
    const is_dir = (entry.kind == .directory);
    // ... generate HTML for this entry ...
}
```

This is the standard Zig pattern: "Zero hidden allocations." We reuse the iterator's internal state to walk through the directory entries one by one.

## Serving the Data

To serve actual file content, we use `request.respondStreaming`. This is more efficient than reading the whole file into memory. We read the file in chunks (16KB) and pipe it directly to the network writer.

```zig
var buf: [16384]u8 = undefined;
while (true) {
    const read = try file.read(&buf);
    if (read == 0) break;
    try response.writer.writeAll(buf[0..read]);
}
```

This keeps the memory footprint of our server constant, regardless of whether we're serving a 1KB text file or a 10GB ISO image.
