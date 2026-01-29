# Part 7: The Final Polish - Embedded CSS and Deployment

A tool is only as good as its user interface. Even a CLI tool that generates HTML needs to look decent. But we aren't going to pull in a 2MB CSS framework from a CDN.

## The `@embedFile` Trick

Zig allows you to include any file directly into your binary at compile time. In `src/http.zig`, we do this with our CSS:

```zig
const style_css = @embedFile("style.css");
```

This variable `style_css` is now a `[]const u8` containing the entire content of our stylesheet. When we generate the directory listing, we dump this string into a `<style>` tag.

The result? One binary file. No external folders. No missing assets. It is completely self-contained.

## Dynamic Port Binding

If the user tries to run the server on a port that is already in use, we don't just crash. We catch the error and try the next port.

```zig
break address.listen(.{ .reuse_address = true }) catch |err| {
    if (err == error.AddressInUse) {
        std.debug.print("Port {d} in use, trying next...\n", .{port});
        port += 1;
        continue;
    }
    return err;
};
```

This is the kind of small UX detail that separates amateur scripts from professional tools.

## Clean Output and Method Support

A professional tool shouldn't dump raw structs to the terminal. We ensure clean output by explicitly formatting the `net.Address` using the `{f}` specifier:

```zig
const addr_str = try std.fmt.bufPrint(&buf, "{f}", .{net_server.listen_address});
std.debug.print("Listening on http://{s}\n", .{addr_str});
```

We also added support for the `HEAD` method, which is often used by health checkers and scrapers to verify a file exists without downloading the entire body.

```zig
if (request.head.method == .GET or request.head.method == .HEAD) {
    try handleGet(allocator, options, request);
}
```

## Conclusion: The Binary the Machine Deserves

By following these steps, we have built a server that is:
1.  **Tiny:** Less than 500KB in its ReleaseSmall static form.
2.  **Fast:** No runtime, no GC pauses, multi-threaded.
3.  **Secure:** Sandboxed and defensive.
4.  **Decent looking:** Modern CSS without the bloat.

Running `zig build -Doptimize=ReleaseSmall` produces the final machine code. This is what it means to build software. No layers of abstraction between you and the hardware. Just logic, data, and Zig.

Go out and write some more Zig. Slay the bloat. 

---
*Zerver-Zig: Zero to Complete.*

```