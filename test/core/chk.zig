test "valid element" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div>Hello</div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
    try testing.expect(!diags.hasErrors());
}

test "valid fragment" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<><span>a</span><span>b</span></>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
    try testing.expect(!diags.hasErrors());
}

test "valid expression block" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    const name = "world";
        \\    return (<p>Hello {name}!</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expectEqual(0, diags.items.len);
}

test "unclosed tag" {
    const allocator = std.testing.allocator;

    // Missing closing </div>
    const source: [:0]const u8 =
        \\(<div>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);
    try testing.expectEqual(Validate.Severity.err, diags.items[0].severity);
}

test "mismatched tags" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div></span>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);
}

test "diagnostic position" {
    const allocator = std.testing.allocator;

    // Introduce an error on line 2, column 5
    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    // Positions are 0-based.
    try testing.expect(diags.items[0].start_line >= 0);
    try testing.expect(diags.items[0].end_line >= diags.items[0].start_line);
}

test "diagnostic message" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.items.len > 0);
    try testing.expect(diags.items[0].message.len > 0);
}

test "broken line scope" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    const broken = ;
        \\    return (<div>Hello</div>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(diags.hasErrors());
    try testing.expect(diags.items.len > 0);

    const last_line: u32 = 4;
    try testing.expectEqual(@as(u32, 1), diags.items[0].start_line);
    try testing.expect(diags.items[0].end_line < last_line);
}

test "Ast.parse valid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<p>OK</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var result = try zx.Ast.parse(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(!result.diagnostics.hasErrors());
    try testing.expectEqual(0, result.diagnostics.items.len);
}

test "Ast.parse invalid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var result = try zx.Ast.parse(allocator, source, .{});
    defer result.deinit(allocator);

    try testing.expect(result.diagnostics.hasErrors());
    try testing.expect(result.diagnostics.items.len > 0);
}

test "Ast.fmt valid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<p>Hello</p>);
        \\}
        \\const zx = @import("zx");
    ;

    var result = try zx.Ast.fmt(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(!result.diagnostics.hasErrors());
    try testing.expect(result.source != null);
}

test "Ast.fmt invalid" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\(<div>)
    ;

    var result = try zx.Ast.fmt(allocator, source);
    defer result.deinit(allocator);

    try testing.expect(result.source == null);
    try testing.expect(result.diagnostics.hasErrors());
    try testing.expect(result.diagnostics.items.len > 0);
}

test "hasErrors empty" {
    const allocator = std.testing.allocator;

    const source: [:0]const u8 =
        \\pub fn Page(allocator: zx.Allocator) zx.Component {
        \\    return (<span>ok</span>);
        \\}
        \\const zx = @import("zx");
    ;

    var parse_result = try Parser.parse(allocator, source, .zx);
    defer parse_result.deinit(allocator);

    var diags = try Validate.validate(allocator, &parse_result);
    defer diags.deinit();

    try testing.expect(!diags.hasErrors());
}

const std = @import("std");
const testing = std.testing;
const zx = @import("zx");
const Parser = zx.Parse;
const Validate = zx.Validate;
