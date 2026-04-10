const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zboost_module = b.addModule("zboost", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zboost_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zboost",
        .root_module = zboost_module,
    });

    b.installArtifact(zboost_lib);
}
