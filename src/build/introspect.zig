const std = @import("std");
const zx = @import("zx");
const __zx_app_root = @import("zx_app_root");

//__ZX_REEXPORTS__

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    var meta = zx.meta;

    var serializable = try zx.server.SerilizableAppMeta.init(
        allocator,
        &meta,
        .{},
    );

    var aw = std.Io.Writer.Allocating.init(allocator);
    try serializable.serialize(&aw.writer);

    try std.Io.File.stdout().writeStreamingAll(io, aw.written());
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}
