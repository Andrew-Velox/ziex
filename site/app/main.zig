const builtin = @import("builtin");
const zx = @import("zx");

pub fn main(init: zx.Init) !void {
    var app_ctx = AppCtx{ .port = 5588 };

    var app = try zx.App.init(init, zx.io(), zx.allocator, .{ .server = .{ .port = 5588 } }, &app_ctx);
    defer app.deinit();

    try app.start();
}

pub const std_options = zx.std_options;

pub const AppCtx = struct {
    port: u16,
};
