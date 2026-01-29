const std = @import("std");

pub const Options = struct {
    listen_address: []const u8 = "0.0.0.0",
    listen_port: u16 = 8000,
    folder: []const u8 = ".",
    enable_tcp: bool = false,
    tcp_with_tls: bool = false,
    rules_file: ?[]const u8 = null,
    enable_upload: bool = false,
    https: bool = false,
    cert_file: ?[]const u8 = null,
    key_file: ?[]const u8 = null,
    domain: []const u8 = "local.host",
    verbose: bool = false,
    basic_auth: ?[]const u8 = null,
    realm: []const u8 = "Please enter username and password",
    silent: bool = false,
    sandbox: bool = false,
    http1_only: bool = false,
    max_file_size: u64 = 50 * 1024 * 1024,
    max_dump_body_size: i64 = -1,
    python_style: bool = false,
    cors: bool = false,
    live_server: bool = false,
    proxy: ?[]const u8 = null,
    fallback_file: ?[]const u8 = null,
    headers: std.ArrayList(HttpHeader),
    allocator: std.mem.Allocator,

    owned_strings: std.ArrayList([]const u8),

    pub const HttpHeader = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn deinit(self: *Options) void {
        for (self.owned_strings.items) |str| {
            self.allocator.free(str);
        }
        self.owned_strings.deinit(self.allocator);
        self.headers.deinit(self.allocator);
    }

    fn dupe(self: *Options, str: []const u8) ![]const u8 {
        const d = try self.allocator.dupe(u8, str);
        try self.owned_strings.append(self.allocator, d);
        return d;
    }
};

fn printHelp() void {
    std.debug.print("Zerver Pro (Zig Edition)\n\n", .{});
    std.debug.print("Usage: zerver [options] [path]\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  -listen <addr:port>  Bind address and port (default: 0.0.0.0:8000)\n", .{});
    std.debug.print("  -port <port>         Listen port\n", .{});
    std.debug.print("  -path <path>         Root folder to serve (default: .)\n", .{});
    std.debug.print("  -ls, -live-server    Enable Live Reload + Remote Logging\n", .{});
    std.debug.print("  -proxy <url>         Reverse proxy to a backend (SSR support)\n", .{});
    std.debug.print("  -basic-auth <u:p>    Enable Basic Authentication\n", .{});
    std.debug.print("  -upload              Enable PUT method for file uploads\n", .{});
    std.debug.print("  -cors                Enable permissive CORS headers\n", .{});
    std.debug.print("  -file <path>         Fallback file for SPA routing\n", .{});
    std.debug.print("  -verbose             Enable request logging\n", .{});
    std.debug.print("  -silent              Disable all output\n", .{});
    std.debug.print("  -h, -help            Show this help menu\n", .{});
}

pub fn parseOptions(allocator: std.mem.Allocator) !Options {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip exe name

    var opts = Options{
        .headers = .{},
        .allocator = allocator,
        .owned_strings = .{}, 
    };
    errdefer opts.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-listen")) {
            if (args.next()) |val| {
                if (std.mem.indexOfScalar(u8, val, ':')) |idx| {
                    opts.listen_address = try opts.dupe(val[0..idx]);
                    opts.listen_port = std.fmt.parseInt(u16, val[idx + 1 ..], 10) catch opts.listen_port;
                } else {
                    opts.listen_address = try opts.dupe(val);
                }
            }
        } else if (std.mem.eql(u8, arg, "-port")) {
            if (args.next()) |val| opts.listen_port = try std.fmt.parseInt(u16, val, 10);
        } else if (std.mem.eql(u8, arg, "-path")) {
            if (args.next()) |val| opts.folder = try opts.dupe(val);
        } else if (std.mem.eql(u8, arg, "-ls") or std.mem.eql(u8, arg, "-live-server")) {
            opts.live_server = true;
        } else if (std.mem.eql(u8, arg, "-proxy")) {
            if (args.next()) |val| opts.proxy = try opts.dupe(val);
        } else if (std.mem.eql(u8, arg, "-basic-auth")) {
            if (args.next()) |val| opts.basic_auth = try opts.dupe(val);
        } else if (std.mem.eql(u8, arg, "-upload")) {
            opts.enable_upload = true;
        } else if (std.mem.eql(u8, arg, "-cors")) {
            opts.cors = true;
        } else if (std.mem.eql(u8, arg, "-file")) {
            if (args.next()) |val| opts.fallback_file = try opts.dupe(val);
        } else if (std.mem.eql(u8, arg, "-verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "-silent")) {
            opts.silent = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "-help")) {
            printHelp();
            std.process.exit(0);
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            opts.folder = try opts.dupe(arg);
        }
    }

    return opts;
}