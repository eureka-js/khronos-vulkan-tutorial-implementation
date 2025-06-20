const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name        = "vulkan-triangle",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target           = target,
            .optimize         = optimize,
        }),
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

    //NOTE: Will have to use local (non system) libraries because I will have to
    //comment out SIMD related functions with corresponding preprocessor directives
    //that cause linkage errors (Zig bug due to it being unfinished?), and use plain c ones. (2025-06-21)

    const cglmLib = b.addLibrary(.{
        .name        = "cglm",
        .root_module = b.createModule(.{
            .target   = target,
            .optimize = optimize,
        }),
    });
    cglmLib.installHeadersDirectory(b.path("libs/cglm/include/"), ".", .{});
    cglmLib.addCSourceFiles(.{
        .files = &.{
            "libs/cglm/src/vec2.c",
            "libs/cglm/src/vec3.c",
            "libs/cglm/src/mat4.c",
        },
        .flags = &.{},
    });
    cglmLib.linkLibC();
    exe.linkLibrary(cglmLib);

    const stbLib = b.addLibrary(.{
        .name       = "stb",
        .root_module = b.createModule(.{
            .target   = target,
            .optimize = optimize,
        }),
    });
    stbLib.installHeadersDirectory(b.path("libs/stb/"), ".", .{});
    stbLib.addIncludePath(b.path("libs/stb/"));
    stbLib.addCSourceFile(.{
        .file = b.addWriteFiles().add(
            "stb_image_stub.c",
            \\#define STB_IMAGE_IMPLEMENTATION
            \\#include <stb_image.h>
        ),
    });
    stbLib.linkLibC();
    exe.linkLibrary(stbLib);
}
