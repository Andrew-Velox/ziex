const std = @import("std");
const ziex = @import("ziex");

pub fn build(b: *std.Build) void {
    const tzx = ziex.addTranslateZx(b, .{
        .root_source_file = b.path("component/root.zx"),
    });
    const ui_mod = tzx.addModule("ui");
    _ = ui_mod;
}
