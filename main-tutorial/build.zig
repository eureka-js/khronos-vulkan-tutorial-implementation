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

    // NOTE: I will have to use a local (non system) cglm library because I will have to comment out a SIMD-related function part
    // that causes linkage errors because it calls a C function that is defined as "static inline __attribute((always_inline))'
    // inside a C header file (such functions don't have a symbol that Zig can link to?);
    // instead, I will use the plain C implementation. (2025-06-21)
    const cglmLib = b.addLibrary(.{
        .name        = "cglm",
        .root_module = b.createModule(.{
            .target   = target,
            .optimize = optimize,
        }),
    });
    cglmLib.installHeadersDirectory(b.path("../libs/cglm/include/"), ".", .{});
    cglmLib.addCSourceFiles(.{
        .files = &.{
            "../libs/cglm/src/vec2.c",
            "../libs/cglm/src/vec3.c",
            "../libs/cglm/src/mat4.c",
        },
    });
    cglmLib.linkLibC();
    exe.linkLibrary(cglmLib);

    const stbLib = b.addLibrary(.{
        .name        = "stb",
        .root_module = b.createModule(.{
            .target   = target,
            .optimize = optimize,
        }),
    });
    stbLib.installHeadersDirectory(b.path("../libs/stb/"), ".", .{});
    stbLib.addIncludePath(b.path("../libs/stb/"));
    stbLib.addCSourceFile(.{
        .file = b.addWriteFiles().add(
            "stb_image_stub.c",
            \\#define STB_IMAGE_IMPLEMENTATION
            \\#include <stb_image.h>
        ),
    });
    stbLib.linkLibC();
    exe.linkLibrary(stbLib);

    const tinyObjLoaderLib = b.addLibrary(.{
        .name        = "tinyObjLoader",
        .root_module = b.createModule(.{
            .target   = target,
            .optimize = optimize,
        }),
    });
    tinyObjLoaderLib.installHeadersDirectory(b.path("../libs/tinyobjloader-c/"), ".", .{});
    tinyObjLoaderLib.addIncludePath(b.path("../libs/tinyobjloader-c/"));
    tinyObjLoaderLib.addCSourceFile(.{
        .file = b.addWriteFiles().add(
            "tiny_obj_loader_c.c",
            \\#define TINYOBJ_LOADER_C_IMPLEMENTATION
            \\#include <tiny_obj_loader_c.h>
        )
    });
    tinyObjLoaderLib.linkLibC();
    exe.linkLibrary(tinyObjLoaderLib);

    const vert = b.addSystemCommand(&.{"glslc", "shaders/shader.vert", "-o", "shaders/vert.spv"});
    const frag = b.addSystemCommand(&.{"glslc", "shaders/shader.frag", "-o", "shaders/frag.spv"});
    const shadersStep = b.step("shaders", "Compile GLSL shaders to SPIR-V");
    shadersStep.dependOn(&vert.step);
    shadersStep.dependOn(&frag.step);

    const withShadersStep = b.step("with-shaders", "Compile both GLSL shaders to SPIR-V, and the program");
    withShadersStep.dependOn(shadersStep);
    withShadersStep.dependOn(&exe.step);
}
