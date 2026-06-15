const std = @import("std");
const zx = @import("zx");
const Context = @import("Context.zig");

pub fn main(init: zx.Init) !void {
    var ctx: Context = .{ .db = try .init(zx.io(), zx.allocator, dbUri(init)) };
    var app = try zx.App.init(init, zx.io(), zx.allocator, .{}, &ctx);
    defer app.deinit();

    try app.start();
}

fn dbUri(init: zx.Init) []const u8 {
    if (zx.platform.isClient()) return "";
    const environ: std.process.Environ = init.minimal.environ;
    return environ.getAlloc(zx.allocator, "DATABASE_URL") catch
        "postgresql://postgres:db_password@localhost:5432/ziex";
}

pub const std_options = zx.std_options;
