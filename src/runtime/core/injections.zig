const std = @import("std");
const zx = @import("../../root.zig");
const Build = @import("../../Build.zig");
const tree = @import("tree.zig");

const Allocator = std.mem.Allocator;
const Component = zx.Component;

/// Structured injections produced by the build system.
const injs: []const Build.AddElementOptions = @import("injections");

pub fn inject(allocator: Allocator, page: *Component) void {
    const rendered = comptime .{
        .head_starting = renderSlot(.head, .starting),
        .head_ending = renderSlot(.head, .ending),
        .body_starting = renderSlot(.body, .starting),
        .body_ending = renderSlot(.body, .ending),
    };

    if (rendered.head_starting.len > 0) {
        if (tree.getElementByName(page, allocator, .head)) |el|
            tree.prependChild(el, allocator, .{ .text = rendered.head_starting }) catch {};
    }
    if (rendered.head_ending.len > 0) {
        if (tree.getElementByName(page, allocator, .head)) |el|
            tree.appendChild(el, allocator, .{ .text = rendered.head_ending }) catch {};
    }
    if (rendered.body_starting.len > 0) {
        if (tree.getElementByName(page, allocator, .body)) |el|
            tree.prependChild(el, allocator, .{ .text = rendered.body_starting }) catch {};
    }
    if (rendered.body_ending.len > 0) {
        if (tree.getElementByName(page, allocator, .body)) |el|
            tree.appendChild(el, allocator, .{ .text = rendered.body_ending }) catch {};
    }
}

fn renderSlot(
    comptime parent: Build.AddElementOptions.Parent,
    comptime position: Build.AddElementOptions.Position,
) []const u8 {
    comptime var matching: []const Build.AddElementOptions = &.{};
    inline for (injs) |inj| {
        if (inj.parent == parent and inj.position == position) {
            matching = matching ++ &[_]Build.AddElementOptions{inj};
        }
    }

    // Stable insertion sort by priority (lowest first). A stable sort keeps
    // equal-priority injections in the order they were added.
    comptime var sorted: [matching.len]Build.AddElementOptions = matching[0..matching.len].*;
    if (sorted.len > 1) {
        inline for (1..sorted.len) |i| {
            const key = sorted[i];
            comptime var j = i;
            inline while (j > 0 and sorted[j - 1].priority > key.priority) : (j -= 1) {
                sorted[j] = sorted[j - 1];
            }
            sorted[j] = key;
        }
    }

    comptime var str: []const u8 = "";
    inline for (sorted) |inj| {
        const comp = comptime toComponent(inj.element);
        str = str ++ renderComponent(comp);
    }
    return str;
}

fn renderComponent(comptime comp: Component) []const u8 {
    comptime {
        var buf: [1 << 16]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buf);
        comp.render(&writer, .{}) catch |err| @compileError(
            "failed to render zx injection: " ++ @errorName(err),
        );
        const len = writer.buffered().len;
        const final: [len]u8 = buf[0..len].*;
        return &final;
    }
}

fn toComponent(comptime elem: Build.AddElementOptions.ElementDef) Component {
    comptime {
        var attrs: [elem.attributes.len]zx.Element.Attribute = undefined;
        for (elem.attributes, 0..) |attr, i| {
            attrs[i] = .{ .name = attr.name, .value = attr.value };
        }
        const attrs_final = attrs;

        var children: ?[]const Component = null;
        if (elem.children) |defs| {
            var kids: [defs.len]Component = undefined;
            for (defs, 0..) |child, i| {
                kids[i] = toComponent(child);
            }
            const kids_final = kids;
            children = &kids_final;
        }

        return .{ .element = .{
            .tag = elem.tag,
            .attributes = &attrs_final,
            .children = children,
        } };
    }
}
