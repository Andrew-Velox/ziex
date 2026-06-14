const std = @import("std");
const zx = @import("zx");

pub fn main(init: zx.Init) !void {
    const port = getPort(init);
    var app = try zx.App(void).init(init, zx.io(), zx.allocator, .{
        .server = .{
            .port = port,
            .address = "0.0.0.0",
        },
    }, {});
    defer app.deinit();

    try app.start();
}

fn getPort(init: zx.Init) u16 {
    if (zx.platform.isClient()) return 3000;
    const environ: std.process.Environ = init.minimal.environ;
    const port_str = environ.getAlloc(zx.allocator, "PORT") catch return 3000;
    defer zx.allocator.free(port_str);
    return std.fmt.parseInt(u16, port_str, 10) catch 3000;
}

pub const std_options = zx.std_options;
