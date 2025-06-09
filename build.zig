const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exeModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    const exe       = b.addExecutable(.{
        .name        = "vulkan-triangle",
        .root_module = exeModule,
    });
    b.installArtifact(exe);

    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("pthread");
    exe.linkSystemLibrary("x11");
    exe.linkSystemLibrary("xxf86vm");
    exe.linkSystemLibrary("xrandr");
    exe.linkSystemLibrary("xi");

    //NOTE: Will have to use the local (non system) cglm library because I will have to
    //comment out SIMD related functions with corresponding preprocessor directives
    //that cause linkage errors (Zig bug due to it being unfinished?), and use plain c ones. (2025-04-21)
    const cglmModule  = b.createModule(.{
        .target   = target,
        .optimize = optimize,
    });
    const cglm        = b.addLibrary(.{
        .name        = "cglm",
        .root_module = cglmModule,
    });
    cglm.addCSourceFiles(.{
        .files = &.{
            "libs/cglm/src/vec2.c",
            "libs/cglm/src/vec3.c",
            "libs/cglm/src/mat4.c",
        },
        .flags = &.{},
    });
    cglm.installHeadersDirectory(b.path("libs/cglm/include/"), ".", .{});
    cglm.linkLibC();
    exe.linkLibrary(cglm);
}
