const std = @import("std");
const __zx_app_root = @import("zx_app_root");

const template = @embedFile("introspect.zig");
const marker = "//__ZX_REEXPORTS__";

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var aw = std.Io.Writer.Allocating.init(init.arena.allocator());
    defer aw.deinit();

    const idx = std.mem.indexOf(u8, template, marker) orelse return error.MarkerMissing;
    try aw.writer.writeAll(template[0..idx]);

    inline for (@typeInfo(__zx_app_root).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, "main")) continue;
        const ptr = @typeInfo(@TypeOf(&@field(__zx_app_root, decl.name)));
        if (comptime ptr.pointer.is_const) {
            try aw.writer.print(
                "pub const {s} = __zx_app_root.{s};\n",
                .{ decl.name, decl.name },
            );
        } else {
            try aw.writer.print(
                "pub const {s} = &__zx_app_root.{s};\n",
                .{ decl.name, decl.name },
            );
        }
    }

    try aw.writer.writeAll(template[idx + marker.len ..]);

    try std.Io.File.stdout().writeStreamingAll(io, aw.written());
}
