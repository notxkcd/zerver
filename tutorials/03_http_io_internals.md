# Part 3: The HTTP Machine and the New I/O

Zig 0.15 introduced one of the most significant changes in the language's history: the `std.Io` namespace. It replaced the old `std.io.Reader` pattern with a more explicit, performant system.

## Understanding `std.Io.Reader` and `Writer`

In previous versions, a reader was just an interface. In 0.15, `std.Io.Reader` is a struct that manages a buffer. This is a game-changer for networking. It means the reader *owns* the memory it's using to stage incoming data.

When a client connects to our server, we don't just hand the socket to the HTTP server. We wrap it in these new buffered interfaces:

```zig
var read_buffer: [8192]u8 = undefined;
var write_buffer: [8192]u8 = undefined;

// Create the network interfaces using the connection stream
var net_reader = conn.stream.reader(&read_buffer);
var net_writer = conn.stream.writer(&write_buffer);

// Pass pointers to the internal interfaces to the HTTP server
var http_server = std.http.Server.init(net_reader.interface(), &net_writer.interface);
```

## Multi-threading without the Bloat

We use `std.Thread.spawn` to handle every connection. Unlike Go's "Goroutines," which are multiplexed onto system threads by a complex scheduler, Zig's threads are actual OS threads. 

```zig
while (true) {
    const conn = try net_server.accept();
    _ = try std.Thread.spawn(.{}, handleConnection, .{ allocator, options, conn });
}
```

This is simple and direct. For a directory-serving tool, the overhead of spawning a thread is negligible compared to the complexity of an async runtime. It’s also much easier to debug with standard tools like `gdb` or `lldb`.

## The Request Lifecycle

Once inside `handleConnection`, we call `http_server.receiveHead()`. This reads the HTTP method, the path, and the headers into our `read_buffer`. If the headers are too large for the 8KB buffer, the server returns an error—protecting us from basic Denial of Service attacks without writing a single extra line of code.
