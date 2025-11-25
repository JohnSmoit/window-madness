// This builds both the c and zig source code for the windowing madness samples
const std = @import("std");


pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vk_mod = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"), 
    }).module("vulkan-zig");

    const exe = b.addExecutable(.{
        .name = "windowing_madness",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/vk_x11.zig"),

            .target = target,
            .optimize = optimize,
        }),
    });
    
    exe.root_module.linkSystemLibrary("X11", .{});
    exe.root_module.addImport("vulkan", vk_mod);

    exe.root_module.link_libc = true;

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
