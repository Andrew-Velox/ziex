const App = @import("../App.zig");
const impl = @import("../../client/Client.zig");

pub const Client = impl.Client;

pub const run = impl.Client.run;

pub fn app() App {
    return .{ .userdata = null, .vtable = &vtable };
}

fn vtStart(_: ?*anyopaque) anyerror!void {
    return impl.Client.run();
}

const vtable = App.VTable{
    .start = &vtStart,
    .stop = App.failing_vtable.stop,
    .deinit = App.failing_vtable.deinit,
    .info = App.failing_vtable.info,
};
