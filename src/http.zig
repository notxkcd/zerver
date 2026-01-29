const std = @import("std");
const Options = @import("options.zig").Options;
const icons = @import("icons.zig");

const style_css = @embedFile("style.css");

var last_change: i128 = 0;
var last_changed_file: [256]u8 = undefined;
var last_changed_file_len: usize = 0;
var live_server_mutex: std.Thread.Mutex = .{};

pub fn start(allocator: std.mem.Allocator, options: Options) !void {
    var port = options.listen_port;
    var net_server: std.net.Server = while (true) {
        const address = std.net.Address.parseIp(options.listen_address, port) catch |err| {
            if (port == 0) return err;
            port = 0;
            continue;
        };
        break address.listen(.{ .reuse_address = true }) catch |err| {
            if (err == error.AddressInUse) {
                std.debug.print("Port {d} in use, trying next...\n", .{port});
                port += 1;
                continue;
            }
            return err;
        };
    };
    defer net_server.deinit();

    if (options.live_server) {
        last_change = std.time.nanoTimestamp();
        _ = try std.Thread.spawn(.{}, watcherThread, .{options.folder});
    }

    if (!options.silent) {
        var buf: [64]u8 = undefined;
        const addr_str = std.fmt.bufPrint(&buf, "{f}", .{net_server.listen_address}) catch "unknown";
        const mode = if (options.proxy != null) "Proxy Mode" else if (options.live_server) "Live Server" else "Static Server";
        std.debug.print("\n------------------------------------------\n", .{});
        std.debug.print("🚀 Zerver Pro (Zig Edition)\n", .{});
        std.debug.print("📂 Root: {s}\n", .{options.folder});
        std.debug.print("🌐 URL:  http://{s}\n", .{addr_str});
        std.debug.print("🛠️ Mode: {s}\n", .{mode});
        std.debug.print("------------------------------------------\n\n", .{});
    }

    while (true) {
        const conn = try net_server.accept();
        _ = try std.Thread.spawn(.{}, handleConnection, .{ allocator, options, conn });
    }
}

fn watcherThread(folder: []const u8) void {
    var last_scan = last_change;
    while (true) {
        std.Thread.sleep(100 * std.time.ns_per_ms);
        var changed_name: [256]u8 = undefined;
        var name_len: usize = 0;
        if (checkFolderChanged(folder, last_scan, &changed_name, &name_len)) {
            live_server_mutex.lock();
            last_change = std.time.nanoTimestamp();
            last_scan = last_change;
            @memcpy(last_changed_file[0..name_len], changed_name[0..name_len]);
            last_changed_file_len = name_len;
            live_server_mutex.unlock();
        }
    }
}

fn checkFolderChanged(folder: []const u8, last_time: i128, name_buf: *[256]u8, name_len: *usize) bool {
    var dir = std.fs.cwd().openDir(folder, .{ .iterate = true }) catch return false;
    defer dir.close();
    return checkDirRecursive(dir, last_time, name_buf, name_len);
}

fn checkDirRecursive(dir: std.fs.Dir, last_time: i128, name_buf: *[256]u8, name_len: *usize) bool {
    var iter = dir.iterate();
    while (iter.next() catch return false) |entry| {
        if (entry.name.len > 0 and entry.name[0] == '.') continue;
        const stat = dir.statFile(entry.name) catch continue;
        if (stat.mtime > last_time) {
            const final_len = @min(entry.name.len, 255);
            @memcpy(name_buf[0..final_len], entry.name[0..final_len]);
            name_len.* = final_len;
            return true;
        }
        if (entry.kind == .directory) {
            var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
            defer sub_dir.close();
            if (checkDirRecursive(sub_dir, last_time, name_buf, name_len)) return true;
        }
    }
    return false;
}

fn handleConnection(allocator: std.mem.Allocator, options: Options, conn: std.net.Server.Connection) void {
    defer conn.stream.close();
    var read_buffer: [8192]u8 = undefined;
    var write_buffer: [8192]u8 = undefined;
    var net_reader = conn.stream.reader(&read_buffer);
    var net_writer = conn.stream.writer(&write_buffer);
    var http_server = std.http.Server.init(net_reader.interface(), &net_writer.interface);
    var request = http_server.receiveHead() catch return;
    handleRequest(allocator, options, &request) catch |err| {
        if (options.verbose) std.debug.print("Request Error: {any}\n", .{err});
    };
}

fn handleRequest(allocator: std.mem.Allocator, options: Options, request: *std.http.Server.Request) !void {
    const path = request.head.target;
    
    if (std.mem.eql(u8, path, "/ls-reload") and options.live_server) {
        try handleReload(request);
        return;
    }

    if (std.mem.eql(u8, path, "/ls-log") and request.head.method == .POST) {
        try handleRemoteLog(request);
        return;
    }

    if (options.proxy) |proxy_url| {
        try handleProxy(allocator, options, request, proxy_url);
        return;
    }

    if (options.verbose) {
        std.debug.print("{s} {s}\n", .{ @tagName(request.head.method), path });
    }

    if (options.cors) {
        try request.respond("", .{
            .extra_headers = &.{ 
                .{ .name = "Access-Control-Allow-Origin", .value = "*" },
                .{ .name = "Access-Control-Allow-Methods", .value = "*" },
                .{ .name = "Access-Control-Allow-Headers", .value = "*" },
            },
            .status = .ok,
        });
        if (request.head.method == .OPTIONS) return;
    }

    if (options.basic_auth) |auth| {
        if (!checkAuth(request, auth)) {
            try request.respond("Unauthorized", .{
                .status = .unauthorized,
                .extra_headers = &.{ .{ .name = "WWW-Authenticate", .value = "Basic realm=\"zerver\"" } },
            });
            return;
        }
    }

    if (request.head.method == .GET or request.head.method == .HEAD) {
        try handleGet(allocator, options, request);
    } else if (request.head.method == .PUT and options.enable_upload) {
        try handlePut(allocator, options, request);
    } else {
        try request.respond("Method Not Allowed", .{ .status = .method_not_allowed });
    }
}

fn handleRemoteLog(request: *std.http.Server.Request) !void {
    var buf: [4096]u8 = undefined;
    var reader = request.readerExpectNone(&buf);
    const n = try reader.readSliceShort(&buf);
    std.debug.print("\x1b[32m[BROWSER]\x1b[0m {s}\n", .{buf[0..n]});
    try request.respond("", .{ .status = .ok });
}

fn handleReload(request: *std.http.Server.Request) !void {
    var stream_buffer: [1024]u8 = undefined;
    var response = try request.respondStreaming(&stream_buffer, .{
        .respond_options = .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/event-stream" },
                .{ .name = "Cache-Control", .value = "no-cache" },
                .{ .name = "Connection", .value = "keep-alive" },
            },
        },
    });
    const local_last = last_change;
    while (true) {
        std.Thread.sleep(200 * std.time.ns_per_ms);
        if (last_change > local_last) {
            var msg_buf: [512]u8 = undefined;
            const msg = try std.fmt.bufPrint(&msg_buf, "data: reload:{s}\n\n", .{last_changed_file[0..last_changed_file_len]});
            try response.writer.writeAll(msg);
            break;
        }
        try response.writer.writeAll(": h\n\n");
    }
    try response.end();
}

fn handleProxy(allocator: std.mem.Allocator, options: Options, request: *std.http.Server.Request, proxy_url: []const u8) !void {
    _ = allocator; _ = options; _ = proxy_url;
    try request.respond("Proxying temporarily disabled.", .{ .status = .not_implemented });
}

fn injectLiveReload(writer: anytype) !void {
    try writer.writeAll("<style>.vzig-pulse { outline: 4px solid #4caf50; outline-offset: -4px; animation: vzig-fade 2s forwards; } @keyframes vzig-fade { from { outline-color: #4caf50; } to { outline-color: transparent; } }</style>");
    try writer.writeAll("<script>(function() { ");
    try writer.writeAll("const oldLog = console.log; ");
    try writer.writeAll("console.log = (...args) => { fetch('/ls-log', { method: 'POST', body: args.join(' ') }); oldLog(...args); }; ");
    try writer.writeAll("const source = new EventSource('/ls-reload'); ");
    try writer.writeAll("source.onmessage = function(event) { if (event.data.startsWith('reload')) { ");
    try writer.writeAll("const file = event.data.split(':')[1] || 'files'; ");
    try writer.writeAll("const toast = document.createElement('div'); ");
    try writer.writeAll("toast.style = 'position:fixed;top:20px;right:20px;background:#333;color:#fff;padding:12px 20px;border-radius:8px;font-family:sans-serif;z-index:9999;box-shadow:0 4px 12px rgba(0,0,0,0.3);border-left:4px solid #4caf50;'; ");
    try writer.writeAll("toast.innerHTML = '💡 <b>Update Detected</b><br><small>Applying changes to ' + file + '...</small>'; ");
    try writer.writeAll("document.body.appendChild(toast); ");
    try writer.writeAll("setTimeout(() => { window.location.reload(); }, 800); ");
    try writer.writeAll("} }; })();</script>");
}

fn handleGet(allocator: std.mem.Allocator, options: Options, request: *std.http.Server.Request) !void {
    const target = request.head.target;
    const path_only = if (std.mem.indexOfScalar(u8, target, '?')) |idx| target[0..idx] else target;
    var path_buf: [1024]u8 = undefined;
    const decoded_path = std.Uri.percentDecodeBackwards(&path_buf, path_only);
    
    const clean_path = if (std.mem.startsWith(u8, decoded_path, "/")) decoded_path[1..] else decoded_path;
    const full_path = try std.fs.path.join(allocator, &.{ options.folder, clean_path });
    defer allocator.free(full_path);

    if (std.mem.endsWith(u8, full_path, ".php")) {
        try handlePHP(allocator, options, request, full_path);
        return;
    }

    const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
        if (err == error.IsDir) {
            const index_path = try std.fs.path.join(allocator, &.{ full_path, "index.html" });
            defer allocator.free(index_path);
            if (std.fs.cwd().openFile(index_path, .{})) |index_file| {
                defer index_file.close();
                try serveFile(allocator, index_file, request, index_path, options);
                return;
            } else |_| {}
            if (options.fallback_file) |fb| {
                if (std.fs.cwd().openFile(fb, .{})) |fb_file| {
                    defer fb_file.close();
                    try serveFile(allocator, fb_file, request, fb, options);
                    return;
                } else |_| {}
            }
            try serveDirectory(allocator, options, request, full_path, decoded_path);
            return;
        }
        try request.respond("Not Found", .{ .status = .not_found });
        return;
    };
    defer file.close();
    const stat = try file.stat();
    if (stat.kind == .directory) {
        const index_path = try std.fs.path.join(allocator, &.{ full_path, "index.html" });
        defer allocator.free(index_path);
        if (std.fs.cwd().openFile(index_path, .{})) |index_file| {
            defer index_file.close();
            try serveFile(allocator, index_file, request, index_path, options);
            return;
        } else |_| {}
        try serveDirectory(allocator, options, request, full_path, decoded_path);
        return;
    }
    try serveFile(allocator, file, request, full_path, options);
}

fn handlePHP(allocator: std.mem.Allocator, options: Options, request: *std.http.Server.Request, php_file: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{ "php", php_file }, allocator);
    child.stdout_behavior = .Pipe;
    try child.spawn();
    const output = try child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(output);
    _ = try child.wait();
    var stream_buffer: [1024]u8 = undefined;
    var response = try request.respondStreaming(&stream_buffer, .{
        .respond_options = .{ .extra_headers = &.{ .{ .name = "Content-Type", .value = "text/html; charset=utf-8" } } },
    });
    try response.writer.writeAll(output);
    if (options.live_server) try injectLiveReload(&response.writer);
    try response.end();
}

fn getMimeType(path: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(extension, ".html") or std.ascii.eqlIgnoreCase(extension, ".htm")) return "text/html; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(extension, ".css")) return "text/css; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(extension, ".js")) return "application/javascript; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(extension, ".json")) return "application/json; charset=utf-8";
    if (std.ascii.eqlIgnoreCase(extension, ".png")) return "image/png";
    if (std.ascii.eqlIgnoreCase(extension, ".jpg") or std.ascii.eqlIgnoreCase(extension, ".jpeg")) return "image/jpeg";
    if (std.ascii.eqlIgnoreCase(extension, ".gif")) return "image/gif";
    if (std.ascii.eqlIgnoreCase(extension, ".svg")) return "image/svg+xml";
    if (std.ascii.eqlIgnoreCase(extension, ".txt")) return "text/plain; charset=utf-8";
    return "application/octet-stream";
}

fn serveFile(allocator: std.mem.Allocator, file: std.fs.File, request: *std.http.Server.Request, path: []const u8, options: Options) !void {
    const stat = try file.stat();
    const mime = getMimeType(path);
    const is_html = std.mem.indexOf(u8, mime, "text/html") != null;
    
    var stream_buffer: [1024]u8 = undefined;
    var response = try request.respondStreaming(&stream_buffer, .{
        .content_length = if (is_html and options.live_server) null else stat.size,
        .respond_options = .{ .extra_headers = &.{ .{ .name = "Content-Type", .value = mime } } },
    });
    if (request.head.method == .HEAD) { try response.end(); return; }

    if (is_html and options.live_server) {
        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(content);
        
        var line_num: usize = 1;
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |line| {
            var line_it = std.mem.splitScalar(u8, line, '<');
            while (line_it.next()) |part| {
                if (part.len > 0 and std.ascii.isAlphabetic(part[0])) {
                    try response.writer.writeAll("<");
                    // Simple injection: find the first space or > after the tag name
                    if (std.mem.indexOfAny(u8, part, " >")) |idx| {
                        try response.writer.writeAll(part[0..idx]);
                        try response.writer.print(" data-vzig-line=\"{d}\"", .{line_num});
                        try response.writer.writeAll(part[idx..]);
                    } else {
                        try response.writer.writeAll(part);
                    }
                } else if (line_it.index == 0) {
                    try response.writer.writeAll(part);
                } else {
                    try response.writer.writeAll("<");
                    try response.writer.writeAll(part);
                }
            }
            try response.writer.writeAll("\n");
            line_num += 1;
        }
        try injectLiveReload(&response.writer);
    } else {
        var buf: [16384]u8 = undefined;
        while (true) {
            const read = try file.read(&buf);
            if (read == 0) break;
            try response.writer.writeAll(buf[0..read]);
        }
    }
    try response.end();
}

fn getFileIcon(entry: std.fs.Dir.Entry) []const u8 {
    if (entry.kind == .directory) return icons.folder;
    const extension = std.fs.path.extension(entry.name);
    if (std.ascii.eqlIgnoreCase(extension, ".zig")) return icons.zig;
    if (std.ascii.eqlIgnoreCase(extension, ".py")) return icons.python;
    if (std.ascii.eqlIgnoreCase(extension, ".js") or std.ascii.eqlIgnoreCase(extension, ".ts") or std.ascii.eqlIgnoreCase(extension, ".tsx") or std.ascii.eqlIgnoreCase(extension, ".jsx")) return icons.javascript;
    if (std.ascii.eqlIgnoreCase(extension, ".rs")) return icons.rust;
    if (std.ascii.eqlIgnoreCase(extension, ".go")) return icons.go;
    if (std.ascii.eqlIgnoreCase(extension, ".html") or std.ascii.eqlIgnoreCase(extension, ".htm")) return icons.html;
    if (std.ascii.eqlIgnoreCase(extension, ".css")) return icons.css;
    if (std.ascii.eqlIgnoreCase(extension, ".json")) return icons.json;
    if (std.ascii.eqlIgnoreCase(extension, ".ex") or std.ascii.eqlIgnoreCase(extension, ".exs")) return icons.elixir;
    if (std.ascii.eqlIgnoreCase(extension, ".hs") or std.ascii.eqlIgnoreCase(extension, ".lhs")) return icons.haskell;
    if (std.ascii.eqlIgnoreCase(extension, ".sh") or std.ascii.eqlIgnoreCase(extension, ".bash") or std.ascii.eqlIgnoreCase(extension, ".zsh")) return icons.shell;
    if (std.ascii.eqlIgnoreCase(extension, ".java") or std.ascii.eqlIgnoreCase(extension, ".jar")) return icons.java;
    if (std.ascii.eqlIgnoreCase(extension, ".pdf")) return icons.pdf;
    if (std.ascii.eqlIgnoreCase(extension, ".jpg") or std.ascii.eqlIgnoreCase(extension, ".jpeg") or std.ascii.eqlIgnoreCase(extension, ".png") or std.ascii.eqlIgnoreCase(extension, ".gif") or std.ascii.eqlIgnoreCase(extension, ".svg")) return icons.image;
    if (std.ascii.eqlIgnoreCase(extension, ".mp4") or std.ascii.eqlIgnoreCase(extension, ".mov") or std.ascii.eqlIgnoreCase(extension, ".avi")) return icons.video;
    if (std.ascii.eqlIgnoreCase(extension, ".zip") or std.ascii.eqlIgnoreCase(extension, ".tar") or std.ascii.eqlIgnoreCase(extension, ".gz") or std.ascii.eqlIgnoreCase(extension, ".7z")) return icons.archive;
    if (std.ascii.eqlIgnoreCase(extension, ".exe") or std.ascii.eqlIgnoreCase(extension, ".bin")) return icons.settings;
    return icons.file;
}

fn serveDirectory(allocator: std.mem.Allocator, options: Options, request: *std.http.Server.Request, full_path: []const u8, web_path: []const u8) !void {
    var dir = std.fs.cwd().openDir(full_path, .{ .iterate = true }) catch {
        try request.respond("Forbidden", .{ .status = .forbidden });
        return;
    };
    defer dir.close();
    var html = std.ArrayList(u8){};
    defer html.deinit(allocator);
    const w = html.writer(allocator);
    try w.writeAll("<html><head><title>Listing</title><style>");
    try w.writeAll(style_css);
    try w.writeAll("</style></head><body><div class=\"container\">");
    if (options.live_server) try w.writeAll("<div style=\"background:#4caf50;color:white;padding:5px 15px;border-radius:20px;display:inline-block;margin-bottom:10px;font-size:12px;\">⚡ Live Server Active</div>");
    try w.print("<h1>Listing for {s}</h1><ul>", .{web_path});
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const is_dir = (entry.kind == .directory);
        const icon = getFileIcon(entry);
        try w.print("<li><a href=\"{s}{s}\"><span class=\"icon\">{s}</span> {s}{s}</a></li>", .{entry.name, if(is_dir) "/" else "", icon, entry.name, if(is_dir) "/" else ""});
    }
    try w.writeAll("</ul><div class=\"footer\">Zerver</div></div>");
    if (options.live_server) try injectLiveReload(&w);
    try w.writeAll("</body></html>");
    try request.respond(html.items, .{ .extra_headers = &.{ .{ .name = "Content-Type", .value = "text/html; charset=utf-8" } } });
}

fn handlePut(allocator: std.mem.Allocator, options: Options, request: *std.http.Server.Request) !void {
    const target = request.head.target;
    const full_path = try std.fs.path.join(allocator, &.{ options.folder, target });
    defer allocator.free(full_path);
    if (request.head.content_length) |len| if (len > options.max_file_size) { try request.respond("Too Large", .{ .status = .payload_too_large }); return; };
    if (std.fs.path.dirname(full_path)) |dir_path| std.fs.cwd().makePath(dir_path) catch {};
    const file = try std.fs.cwd().createFile(full_path, .{});
    defer file.close();
    var put_buffer: [8192]u8 = undefined;
    var reader = request.readerExpectNone(&put_buffer);
    var buf: [16384]u8 = undefined;
    var total_read: u64 = 0;
    while (true) {
        const read = try reader.readSliceShort(&buf);
        if (read == 0) break;
        total_read += read;
        if (total_read > options.max_file_size) { try request.respond("Too Large", .{ .status = .payload_too_large }); return; }
        try file.writeAll(buf[0..read]);
    }
    try request.respond("Uploaded", .{ .status = .created });
}

fn checkAuth(request: *std.http.Server.Request, auth: []const u8) bool {
    var it = std.http.HeaderIterator.init(request.head_buffer);
    while (it.next()) |header| if (std.ascii.eqlIgnoreCase(header.name, "Authorization")) {
        if (std.mem.startsWith(u8, header.value, "Basic ")) {
            const encoded = header.value[6..];
            var decode_buf: [256]u8 = undefined;
            const len = (std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return false);
            if (len <= decode_buf.len) {
                std.base64.standard.Decoder.decode(&decode_buf, encoded) catch return false;
                return std.mem.eql(u8, decode_buf[0..len], auth);
            }
        }
    };
    return false;
}
