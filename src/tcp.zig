//! Rule-based TCP Server Implementation.
//! Responds to incoming TCP data based on hot-reloadable pattern-matching rules.

const std = @import("std");
const Options = @import("options.zig").Options;

/// Represents a single matching rule for the TCP server.
pub const Rule = struct {
    /// Human-readable name for the rule.
    name: []const u8 = "unnamed",
    /// Exact match string (if provided).
    match: ?[]const u8 = null,
    /// Partial match string (if provided).
    match_contains: ?[]const u8 = null,
    /// The data to send back when the rule matches.
    response: []const u8 = "",
};

/// Global state for the TCP server, shared across handler threads.
pub const ServerState = struct {
    /// Current list of active rules.
    rules: std.ArrayList(Rule),
    /// Lock ensuring thread-safe access to the rules during hot-reloading.
    lock: std.Thread.RwLock = .{},
    /// Allocator used for rule memory.
    allocator: std.mem.Allocator,

    /// Frees all memory associated with the rules and the state.
    pub fn deinit(self: *ServerState) void {
        self.lock.lock();
        defer self.lock.unlock();
        for (self.rules.items) |rule| {
            self.allocator.free(rule.name);
            if (rule.match) |m| self.allocator.free(m);
            if (rule.match_contains) |mc| self.allocator.free(mc);
            self.allocator.free(rule.response);
        }
        self.rules.deinit(self.allocator);
    }
};

/// Starts the TCP server and its associated file watcher thread.
pub fn start(allocator: std.mem.Allocator, options: Options) !void {
    var port = options.listen_port;
    var server: std.net.Server = while (true) {
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
    defer server.deinit();

    var state = try allocator.create(ServerState);
    state.* = .{
        .rules = std.ArrayList(Rule){},
        .allocator = allocator,
    };
    if (options.rules_file) |file_path| {
        try loadRules(allocator, &state.rules, file_path);
    }

    if (!options.silent) {
        var buf: [64]u8 = undefined;
        const addr_str = std.fmt.bufPrint(&buf, "{f}", .{server.listen_address}) catch "unknown";
        std.debug.print("Listening on tcp://{s}\n", .{addr_str});
    }

    if (options.rules_file) |file_path| {
        _ = try std.Thread.spawn(.{}, watchRules, .{ state, file_path });
    }

    while (true) {
        const conn = try server.accept();
        _ = try std.Thread.spawn(.{}, handleConnection, .{ options, conn, state });
    }
}

/// Watches the rules file for changes and reloads them if the modification time updates.
fn watchRules(state: *ServerState, file_path: []const u8) void {
    var last_mod: i128 = 0;
    if (std.fs.cwd().statFile(file_path)) |stat| {
        last_mod = stat.mtime;
    } else |_| {}

    while (true) {
        std.Thread.sleep(2 * std.time.ns_per_s);
        const stat = std.fs.cwd().statFile(file_path) catch continue;
        if (stat.mtime > last_mod) {
            last_mod = stat.mtime;
            std.debug.print("Reloading TCP rules from {s}\n", .{file_path});
            
            var new_rules = std.ArrayList(Rule){};
            loadRules(state.allocator, &new_rules, file_path) catch |err| {
                std.debug.print("Error reloading rules: {any}\n", .{err});
                continue;
            };

            state.lock.lock();
            const old_rules = state.rules;
            state.rules = new_rules;
            state.lock.unlock();

            // Clean up old rules
            for (old_rules.items) |rule| {
                state.allocator.free(rule.name);
                if (rule.match) |m| state.allocator.free(m);
                if (rule.match_contains) |mc| state.allocator.free(mc);
                state.allocator.free(rule.response);
            }
            var old_copy = old_rules;
            old_copy.deinit(state.allocator);
        }
    }
}

/// Handles an incoming raw TCP connection.
fn handleConnection(options: Options, conn: std.net.Server.Connection, state: *ServerState) void {
    defer conn.stream.close();

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = conn.stream.read(&buf) catch break;
        if (n == 0) break;

        const input = buf[0..n];
        if (options.verbose) {
            std.debug.print("TCP Input: {s}\n", .{input});
        }

        state.lock.lockShared();
        var matched_response: ?[]const u8 = null;
        for (state.rules.items) |rule| {
            if (matchRule(rule, input)) {
                matched_response = rule.response;
                break;
            }
        }
        
        if (matched_response) |resp| {
            conn.stream.writeAll(resp) catch {};
        } else {
            conn.stream.writeAll(":) ") catch {};
        }
        state.lock.unlockShared();
    }
}

/// Checks if an input buffer matches a given rule.
fn matchRule(rule: Rule, input: []u8) bool {
    if (rule.match_contains) |mc| {
        if (std.mem.indexOf(u8, input, mc) != null) return true;
    }
    if (rule.match) |m| {
        if (std.mem.eql(u8, input, m)) return true;
    }
    return false;
}

/// Loads pattern-matching rules from a YAML-ish text file.
fn loadRules(allocator: std.mem.Allocator, rules: *std.ArrayList(Rule), file_path: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_rule: ?Rule = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "- name:")) {
            if (current_rule) |r| try rules.append(allocator, r);
            current_rule = Rule{ .name = try allocator.dupe(u8, std.mem.trim(u8, trimmed[7..], " ")) };
        } else if (std.mem.startsWith(u8, trimmed, "match:")) {
            if (current_rule) |*r| r.match = try allocator.dupe(u8, std.mem.trim(u8, trimmed[6..], " "));
        } else if (std.mem.startsWith(u8, trimmed, "match-contains:")) {
            if (current_rule) |*r| r.match_contains = try allocator.dupe(u8, std.mem.trim(u8, trimmed[15..], " "));
        } else if (std.mem.startsWith(u8, trimmed, "response:")) {
            if (current_rule) |*r| r.response = try allocator.dupe(u8, std.mem.trim(u8, trimmed[9..], " "));
        }
    }
    if (current_rule) |r| try rules.append(allocator, r);
}