const std = @import("std");
const Build = @import("../Build.zig");

pub const AddElementOptions = Build.AddElementOptions;

pub const RouteEntry = struct {
    path: []const u8,
    page_import: ?[]const u8 = null,
    layout_import: ?[]const u8 = null,
    notfound_import: ?[]const u8 = null,
    error_import: ?[]const u8 = null,
    route_import: ?[]const u8 = null,
    proxy_import: ?[]const u8 = null,
};

pub const App = struct {
    injections: []const AddElementOptions = &.{},
    routes: []const RouteEntry = &.{},
};

pub fn readAlloc(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !App {
    const source = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(source);

    if (source.len == 0) return .{};
    const source_z = try std.mem.concatWithSentinel(allocator, u8, &.{source}, 0);
    defer allocator.free(source_z);
    return try std.zon.parse.fromSliceAlloc(App, allocator, source_z, null, .{ .ignore_unknown_fields = true });
}

pub fn free(allocator: std.mem.Allocator, app: App) void {
    std.zon.parse.free(allocator, app);
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    return if (value) |v| try allocator.dupe(u8, v) else null;
}

fn dupeRoute(allocator: std.mem.Allocator, route: RouteEntry) !RouteEntry {
    return .{
        .path = try allocator.dupe(u8, route.path),
        .page_import = try dupeOptional(allocator, route.page_import),
        .layout_import = try dupeOptional(allocator, route.layout_import),
        .notfound_import = try dupeOptional(allocator, route.notfound_import),
        .error_import = try dupeOptional(allocator, route.error_import),
        .route_import = try dupeOptional(allocator, route.route_import),
        .proxy_import = try dupeOptional(allocator, route.proxy_import),
    };
}

pub fn write(io: std.Io, path: []const u8, app: App) !void {
    var aw = std.Io.Writer.Allocating.init(std.heap.page_allocator);
    defer aw.deinit();
    try std.zon.stringify.serializeArbitraryDepth(app, .{ .whitespace = true }, &aw.writer);
    if (std.fs.path.dirname(path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = aw.written() });
}

pub fn setRoutes(io: std.Io, allocator: std.mem.Allocator, path: []const u8, routes: []const RouteEntry) !void {
    const app = try readAlloc(io, allocator, path);
    defer free(allocator, app);

    var owned = try allocator.alloc(RouteEntry, routes.len);
    errdefer allocator.free(owned);
    for (routes, 0..) |route, i| {
        owned[i] = try dupeRoute(allocator, route);
    }

    try write(io, path, .{
        .injections = app.injections,
        .routes = owned,
    });
}

pub fn isWasmlinkInjection(injection: AddElementOptions) bool {
    if (injection.element.tag != .link) return false;
    for (injection.element.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "id") and std.mem.eql(u8, attr.value orelse "", "__$wasmlink")) {
            return true;
        }
    }
    return false;
}

pub fn isJsglueInjection(injection: AddElementOptions) bool {
    if (injection.element.tag != .script) return false;
    for (injection.element.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "defer")) return true;
    }
    return false;
}

pub fn isManagedBuildInjection(injection: AddElementOptions) bool {
    return isWasmlinkInjection(injection) or isJsglueInjection(injection);
}

pub fn mergeBuildInjections(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    build_injections: []const AddElementOptions,
) !void {
    const app = try readAlloc(io, allocator, path);
    defer free(allocator, app);

    var injections = std.array_list.Managed(AddElementOptions).init(allocator);
    defer injections.deinit();

    for (app.injections) |injection| {
        if (!isManagedBuildInjection(injection)) try injections.append(injection);
    }
    try injections.appendSlice(build_injections);

    try write(io, path, .{
        .injections = injections.items,
        .routes = app.routes,
    });
}

pub fn upsertWasmlinkInjection(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    injection: AddElementOptions,
) !void {
    const app = try readAlloc(io, allocator, path);
    defer free(allocator, app);

    var injections = std.array_list.Managed(AddElementOptions).init(allocator);
    defer injections.deinit();

    for (app.injections) |existing| {
        if (!isWasmlinkInjection(existing)) try injections.append(existing);
    }
    try injections.append(injection);

    try write(io, path, .{
        .injections = injections.items,
        .routes = app.routes,
    });
}

pub fn upsertJsglueInjection(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    injection: AddElementOptions,
) !void {
    const app = try readAlloc(io, allocator, path);
    defer free(allocator, app);

    var injections = std.array_list.Managed(AddElementOptions).init(allocator);
    defer injections.deinit();

    for (app.injections) |existing| {
        if (!isJsglueInjection(existing)) try injections.append(existing);
    }
    try injections.append(injection);

    try write(io, path, .{
        .injections = injections.items,
        .routes = app.routes,
    });
}

pub fn appendInjection(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    injection: AddElementOptions,
) !void {
    const app = try readAlloc(io, allocator, path);
    defer free(allocator, app);

    var injection_list = std.array_list.Managed(AddElementOptions).init(allocator);
    defer injection_list.deinit();
    try injection_list.appendSlice(app.injections);
    try injection_list.append(injection);

    try write(io, path, .{
        .injections = injection_list.items,
        .routes = app.routes,
    });
}
