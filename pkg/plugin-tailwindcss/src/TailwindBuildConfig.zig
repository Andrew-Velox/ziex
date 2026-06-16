/// Zig-side config for a Tailwind CSS build.
/// Fields that accept LazyPath are resolved to strings before JSON serialization.
const TailwindBuildConfig = @This();

/// Input CSS file path (required)
input: std.Build.LazyPath,

/// Minify the output [default: false]
minify: bool = false,

/// Optimize the output without full minification [default: false]
optimize: bool = false,

/// Generate a source map [default: false]
map: bool = false,

/// Base directory for resolving imports [default: dirname(input)]
base: ?std.Build.LazyPath = null,

/// Additional source file paths to scan for class names
sources: ?[]const std.Build.LazyPath = null,

pub fn toJsonValue(self: TailwindBuildConfig, b: *std.Build, arena: std.mem.Allocator) !std.json.Value {
    var obj = std.json.ObjectMap.empty;

    // TODO: LazyPath.getPath is not available anymore in zig 0.17, figure out alternative
    const input_path = b.pathJoin(&.{
        b.fmt("{f}", .{b.root.root_dir}),
        b.fmt("{f}", .{self.input}),
    });
    try obj.put(arena, "input", .{ .string = input_path });
    try obj.put(arena, "minify", .{ .bool = self.minify });
    try obj.put(arena, "optimize", .{ .bool = self.optimize });
    try obj.put(arena, "map", .{ .bool = self.map });

    if (self.base) |base| {
        const base_path = b.pathJoin(&.{
            b.fmt("{f}", .{b.root.root_dir}),
            b.fmt("{f}", .{base}),
        });

        try obj.put(arena, "base", .{ .string = base_path });
    }

    if (self.sources) |sources| {
        var arr = try std.json.Array.initCapacity(arena, sources.len);
        for (sources) |source| {
            const source_path = b.pathJoin(&.{
                b.fmt("{f}", .{b.root.root_dir}),
                b.fmt("{f}", .{source}),
            });

            arr.appendAssumeCapacity(.{ .string = source_path });
        }
        try obj.put(arena, "sources", .{ .array = arr });
    }

    return .{ .object = obj };
}

const std = @import("std");
