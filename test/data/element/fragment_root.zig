pub fn Page(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .fragment,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.cmp(
                    FragmentComponent,
                    .{ .src = @src() },
                    .{ .name = "FragmentComponent" },
                    .{},
                ),
            },
        },
    );
}

fn FragmentComponent(allocator: zx.Allocator) zx.Component {
    var _zx = @import("zx").x.allocInit(allocator, .{ .src = @src() });
    return _zx.ele(
        .fragment,
        .{
            .allocator = allocator,
            .children = &.{
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("First"),
                        },
                    },
                ),
                _zx.ele(
                    .p,
                    .{
                        .children = &.{
                            _zx.txt("Second"),
                        },
                    },
                ),
            },
        },
    );
}

const zx = @import("zx");
