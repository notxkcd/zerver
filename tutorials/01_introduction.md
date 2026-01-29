# Part 1: Slaying the Bloat - Why Zig?

Most people look at a web server and see a complex beast that needs thousands of lines of code. The Go version of this project was "simple," but it still relied on a runtime, a garbage collector, and a lot of hidden "magic." In the suckless philosophy, if you don't know exactly what every byte of your program is doing, you don't own the program; the program owns you.

Zig 0.15 is the ultimate tool for reclaiming that ownership. No hidden control flow. No hidden allocations.

## The Build System (`build.zig`)

In modern development, build systems are usually a mess of XML, JSON, or obscure DSLs. In Zig, the build system is just Zig. We want a tool that produces two distinct artifacts:

1.  **Static Binary:** A standalone executable with zero dependencies. Throw it on an Alpine Linux container or a 20-year-old server; it just works.
2.  **Dynamic Binary:** Linked against `libc`. Use this if you want to integrate with system-level logging or specific OS features that require the standard C library.

Here is the logic we implemented in `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // We create a single Module. This is our source code.
    // By creating a module, we avoid recompiling the same logic twice
    // for our two different binary targets.
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The Static Build - This is the default.
    const exe_static = b.addExecutable(.{
        .name = "simplehttpserver-static",
        .root_module = root_module,
    });
    b.installArtifact(exe_static);

    // The Dynamic Build - We explicitly call linkLibC().
    const exe_dynamic = b.addExecutable(.{
        .name = "simplehttpserver-dynamic",
        .root_module = root_module,
    });
    exe_dynamic.linkLibC();
    b.installArtifact(exe_dynamic);
}
```

This is the beauty of Zig. We define the *intent* of our software once, and the build system handles the mechanical details of linking and optimization. We aren't fighting the compiler; we are orchestrating it.
