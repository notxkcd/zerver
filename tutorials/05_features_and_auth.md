# Part 5: Protocol Compliance and Advanced Features

A real-world server needs more than just GET requests. We need security (Basic Auth), data intake (PUT uploads), and limits (Max File Size).

## Full Basic Auth

Basic Auth isn't "secure" without TLS, but it's a standard requirement. In `src/http.zig`, we implement manual Base64 decoding.

```zig
// 1. Find the Authorization header
var it = std.http.HeaderIterator.init(request.head_buffer);
while (it.next()) |header| {
    if (std.ascii.eqlIgnoreCase(header.name, "Authorization")) {
        // 2. Decode the Base64 value
        const encoded = header.value[6..]; // Skip "Basic "
        var decode_buf: [256]u8 = undefined;
        const len = (std.base64.standard.Decoder.calcSizeForSlice(encoded) catch 0);
        if (len <= decode_buf.len) {
            std.base64.standard.Decoder.decode(&decode_buf, encoded) catch {};
            // 3. Compare with the expected user:pass string
            if (std.mem.eql(u8, decode_buf[0..len], auth)) {
                found_auth = true;
            }
        }
    }
}
```

Most developers would use a middleware for this. We write the logic directly into the request handler. It’s clear, easy to audit, and has zero overhead.

## PUT Uploads and Size Limits

To implement the `-upload` feature, we handle the `PUT` method. But we must be careful: we don't want a client to fill up our entire disk.

We enforce the `max_file_size` in two places:
1.  **Header Check:** If the client sends a `Content-Length` header larger than our limit, we reject it immediately.
2.  **Streaming Check:** Some clients might lie about the length. We count every byte we read from the network and kill the connection if it exceeds the limit.

```zig
var total_read: u64 = 0;
while (true) {
    const read = try reader.readSliceShort(&buf);
    if (read == 0) break;
    total_read += read;
    if (total_read > options.max_file_size) {
        try request.respond("Too Large", .{ .status = .payload_too_large });
        return;
    }
    try file.writeAll(buf[0..read]);
}
```

This is defensive programming. Never trust the client.
