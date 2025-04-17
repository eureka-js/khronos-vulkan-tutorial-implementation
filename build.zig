const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "vulkan-triangle",
        .root_module = module,
    });
    b.installArtifact(exe);

    exe.installHeadersDirectory(b.path("libs/cglm/include"), ".", .{});

    // Will have to use local (non system) cglm library because I will have to comment out simd
    // related funtions with corresponding conditional macro statements that cause linkage errors,
    // and use plain c ones.
    // TODO add local cglm static library

    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("x11");
    exe.linkSystemLibrary("xxf86vm");
    exe.linkSystemLibrary("xrandr");
    exe.linkSystemLibrary("xi");
}
