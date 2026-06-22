const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("postgres", .{
        .root_source_file = b.path("src/postgres.zig"),
        .optimize = optimize,
        .target = target,
    });
}
