pub fn GET(ctx: zx.RouteContext) !void {
    try ctx.response.json(.{ .name = "nurul" }, .{});
}

const options: zx.RouteOptions = .{};

const zx = @import("zx");
const std = @import("std");
