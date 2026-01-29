# Part 6: The Watcher - TCP Rules and Hot Reloading

One of the most powerful features of this server is the TCP rules engine. It allows you to define responses for arbitrary TCP data in a YAML-ish rules file. But restarting a server to update a rule is a sign of poor design. We want **Hot Reloading**.

## Thread Safety with `RwLock`

We have multiple threads handling connections and one thread watching the file. To prevent them from stepping on each other, we use a `Read-Write Lock` (`std.Thread.RwLock`).

- **Shared Lock:** Multiple connection handlers can read the rules simultaneously.
- **Exclusive Lock:** Only the watcher thread can have the lock when it’s swapping out the rules.

```zig
// In the watcher thread
state.lock.lock(); // Get exclusive access
const old_rules = state.rules;
state.rules = new_rules; // Swap the rules list
state.lock.unlock(); // Release

// In the connection handler
state.lock.lockShared(); // Get shared read access
// ... match rules ...
state.lock.unlockShared();
```

## The File Watcher Thread

We spawn a separate thread that loops forever, checking the modification time of the rules file.

```zig
fn watchRules(state: *ServerState, file_path: []const u8) void {
    var last_mod: i128 = 0;
    // ... get initial mtime ...

    while (true) {
        std.Thread.sleep(2 * std.time.ns_per_s); // Check every 2 seconds
        const stat = std.fs.cwd().statFile(file_path) catch continue;
        if (stat.mtime > last_mod) {
            last_mod = stat.mtime;
            // ... reload logic ...
        }
    }
}
```

This is significantly more efficient than using OS-specific APIs like `inotify` or `kqueue`. For a simple tool, a 2-second polling loop is perfectly adequate and entirely cross-platform. It keeps the codebase "suckless" and easy to port to any OS that has a filesystem and threads.
