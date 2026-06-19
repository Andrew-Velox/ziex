const std = @import("std");
const core_lang = @import("core_lang");
const docs = @import("html_docs.zig");

const Parse = core_lang.Parse;
const NodeKind = Parse.NodeKind;

/// A located hover target: the documentation Markdown plus the byte span of the
/// token it describes (so the caller can build an LSP range to highlight).
pub const Hover = struct {
    markdown: []const u8,
    start_byte: u32,
    end_byte: u32,
};

/// Parse `source` and, if `offset` falls on an HTML tag name or attribute name,
/// return its hover documentation. Returns null when the cursor is elsewhere
/// (so the caller can fall back to the Zig language server).
///
/// The returned `markdown` is allocated with `arena`.
pub fn hover(arena: std.mem.Allocator, source: []const u8, offset: u32) !?Hover {
    if (offset > source.len) return null;

    var parse = Parse.parse(arena, source, .zx) catch return null;
    defer parse.deinit(arena);

    const root = parse.tree.rootNode();
    const node = root.descendantForByteRange(offset, offset) orelse return null;

    return hoverForNode(arena, &parse, node, source);
}

/// Like `hover`, but returns just the Markdown string (no span). Convenience
/// for callers that don't need the range.
pub fn hoverMarkdown(arena: std.mem.Allocator, source: []const u8, offset: u32) !?[]const u8 {
    const h = try hover(arena, source, offset);
    return if (h) |x| x.markdown else null;
}

fn hoverForNode(arena: std.mem.Allocator, parse: *Parse, node: anytype, source: []const u8) !?Hover {
    const kind = NodeKind.fromNode(node);
    switch (kind) {
        .zx_tag_name => {
            const name = nodeText(node, source);
            const md = try elementMarkdown(arena, name) orelse return null;
            return .{ .markdown = md, .start_byte = node.startByte(), .end_byte = node.endByte() };
        },
        .zx_attribute_name => {
            const attr = nodeText(node, source);
            const tag = enclosingTagName(parse, node, source) orelse "";
            const md = try attributeMarkdown(arena, tag, attr) orelse return null;
            return .{ .markdown = md, .start_byte = node.startByte(), .end_byte = node.endByte() };
        },
        else => return null,
    }
}

/// Build Markdown documentation for an element tag name, or null if unknown.
fn elementMarkdown(arena: std.mem.Allocator, name: []const u8) !?[]const u8 {
    const doc = docs.element(name) orelse return null;

    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    try w.print("**`<{s}>`**", .{doc.name});
    if (doc.interface.len > 0) try w.print(" — {s}", .{doc.interface});
    try w.writeAll("\n\n");

    if (doc.description.len > 0) {
        try w.print("{s}\n", .{doc.description});
    } else if (doc.title.len > 0) {
        try w.print("{s}\n", .{doc.title});
    }

    if (doc.href.len > 0) {
        try w.print("\n[HTML specification]({s})\n", .{doc.href});
    }
    return out.written();
}

/// Build Markdown documentation for an attribute, or null if unknown.
fn attributeMarkdown(arena: std.mem.Allocator, tag: []const u8, attr: []const u8) !?[]const u8 {
    const doc = docs.attribute(tag, attr) orelse return null;

    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;

    if (tag.len > 0) {
        try w.print("**`{s}`** attribute of `<{s}>`\n\n", .{ doc.name, tag });
    } else {
        try w.print("**`{s}`** attribute\n\n", .{doc.name});
    }

    if (doc.description.len > 0) {
        try w.print("{s}\n", .{doc.description});
    }
    if (doc.href.len > 0) {
        try w.print("\n[HTML specification]({s})\n", .{doc.href});
    }
    return out.written();
}

/// Walk up from an attribute-name node to its enclosing start/self-closing tag
/// and return that tag's name.
fn enclosingTagName(parse: *Parse, node: anytype, source: []const u8) ?[]const u8 {
    _ = parse;
    var current = node.parent();
    while (current) |n| : (current = n.parent()) {
        switch (NodeKind.fromNode(n)) {
            .zx_start_tag, .zx_self_closing_element => {
                const name_node = n.childByFieldName("name") orelse return null;
                return nodeText(name_node, source);
            },
            // Stop once we leave the tag entirely.
            .zx_element, .zx_child => return null,
            else => {},
        }
    }
    return null;
}

fn nodeText(node: anytype, source: []const u8) []const u8 {
    const start = node.startByte();
    const end = node.endByte();
    if (start < end and end <= source.len) return source[start..end];
    return "";
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

/// Returns the byte offset of the first occurrence of `needle` in `src`, plus
/// `into` (used to point inside the match).
fn offsetOf(src: []const u8, needle: []const u8, into: u32) u32 {
    const idx = std.mem.indexOf(u8, src, needle).?;
    return @intCast(idx + into);
}

test "hover: element tag name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div class="x">hi</div>);
        \\}
    ;
    // Point at the "div" in the start tag.
    const off = offsetOf(src, "<div", 1);
    const md = (try hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "<div>") != null);
    try testing.expect(std.mem.indexOf(u8, md, "generic flow-content") != null);
    try testing.expect(std.mem.indexOf(u8, md, "specification") != null);
}

test "hover: global attribute name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div class="x">hi</div>);
        \\}
    ;
    const off = offsetOf(src, "class=", 1);
    const md = (try hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "class") != null);
    try testing.expect(std.mem.indexOf(u8, md, "CSS classes") != null);
}

test "hover: element-specific attribute name" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<a href="/x">link</a>);
        \\}
    ;
    const off = offsetOf(src, "href=", 1);
    const md = (try hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "href") != null);
    try testing.expect(std.mem.indexOf(u8, md, "hyperlink points to") != null);
    // The enclosing tag should be reflected.
    try testing.expect(std.mem.indexOf(u8, md, "<a>") != null);
}

test "hover: unknown element returns null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<Foo />);
        \\}
    ;
    const off = offsetOf(src, "<Foo", 1);
    try testing.expect((try hoverMarkdown(arena, src, off)) == null);
}

test "hover: cursor outside tag returns null" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div>hi</div>);
        \\}
    ;
    // Point at "Page" — plain Zig, not an HTML tag.
    const off = offsetOf(src, "Page", 1);
    try testing.expect((try hoverMarkdown(arena, src, off)) == null);
}

test "hover: void element self-closing tag" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const src =
        \\pub fn Page(a: zx.Allocator) zx.Component {
        \\    return (<div><br /></div>);
        \\}
    ;
    const off = offsetOf(src, "<br", 1);
    const md = (try hoverMarkdown(arena, src, off)) orelse return error.NoHover;
    try testing.expect(std.mem.indexOf(u8, md, "<br>") != null);
}
