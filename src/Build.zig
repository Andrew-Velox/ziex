const Build = @This();

const element = @import("element.zig");
const Tag = element.Tag;

pub const AddElementOptions = struct {
    pub const ElementDef = struct {
        pub const Attribute = struct {
            name: []const u8,
            value: ?[]const u8 = null,
        };
        tag: element.Tag,
        children: ?[]const ElementDef = null,
        attributes: []const Attribute = &.{},
    };

    pub const Parent = enum { body, head };
    pub const Position = enum { starting, ending };

    parent: Parent,
    position: Position,
    element: ElementDef,
    priority: u8 = 128,
};
