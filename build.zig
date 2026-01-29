const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Pro Feature: Architecture filtering
    const filter_arch = b.option(std.Target.Cpu.Arch, "arch", "Filter build-all by architecture (e.g. -Darch=x86_64)");

    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
    };

    const build_all_step = b.step("build-all", "Build for all supported targets (filterable via -Darch)");

    for (targets) |t| {
        // Skip if a filter is provided and doesn't match
        if (filter_arch) |arch| {
            if (t.cpu_arch.? != arch) continue;
        }

        const resolved_target = b.resolveTargetQuery(t);
        const root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = resolved_target,
            .optimize = optimize,
        });

        const target_name = b.fmt("{s}-{s}", .{ @tagName(t.cpu_arch.?), @tagName(t.os_tag.?) });

        const exe_static = b.addExecutable(.{
            .name = b.fmt("simplehttpserver-static-{s}", .{target_name}),
            .root_module = root_module,
        });
        const install_static = b.addInstallArtifact(exe_static, .{});
        build_all_step.dependOn(&install_static.step);

        const exe_dynamic = b.addExecutable(.{
            .name = b.fmt("simplehttpserver-dynamic-{s}", .{target_name}),
            .root_module = root_module,
        });
        exe_dynamic.linkLibC();
        const install_dynamic = b.addInstallArtifact(exe_dynamic, .{});
        build_all_step.dependOn(&install_dynamic.step);
    }

    // Default Host Build
    const host_root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_static_host = b.addExecutable(.{
        .name = "simplehttpserver-static",
        .root_module = host_root_module,
    });
    b.installArtifact(exe_static_host);

    const run_cmd = b.addRunArtifact(exe_static_host);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app (static version)");
    run_step.dependOn(&run_cmd.step);
}