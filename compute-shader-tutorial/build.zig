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
        },
    });
    cglmLib.linkLibC();
    exe.linkLibrary(cglmLib);

    const vert = b.addSystemCommand(&.{"glslc", "shaders/shader.vert", "-o", "shaders/vert.spv"});
    const frag = b.addSystemCommand(&.{"glslc", "shaders/shader.frag", "-o", "shaders/frag.spv"});
    const comp = b.addSystemCommand(&.{"glslc", "shaders/shader.comp", "-o", "shaders/comp.spv"});
    const shadersStep = b.step("shaders", "Compile GLSL shaders to SPIR-V");
    shadersStep.dependOn(&vert.step);
    shadersStep.dependOn(&frag.step);
    shadersStep.dependOn(&comp.step);

    const withShadersStep = b.step("with-shaders", "Compile both GLSL shaders to SPIR-V, and the program");
    withShadersStep.dependOn(shadersStep);
    withShadersStep.dependOn(&exe.step);
}
