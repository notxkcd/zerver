//! Main entry point for Zerver-Zig.
const std = @import("std");
const options = @import("options.zig");
const http_server = @import("http.zig");
const tcp_server = @import("tcp.zig");

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    run(allocator) catch |err| {
        std.debug.print("Fatal error: {any}\n", .{err});
        std.process.exit(1);
    };
}

fn run(allocator: std.mem.Allocator) !void {
    var opts = try options.parseOptions(allocator);
    defer opts.deinit();

    if (!opts.silent) {
        std.debug.print("Starting Zerver...\n", .{});
    }

    if (opts.enable_tcp) {
        try tcp_server.start(allocator, opts);
    } else {
        try http_server.start(allocator, opts);
    }
}
