const std = @import("std");
const builtin = @import("builtin");

const zx = @import("root.zig");
const server = @import("runtime/server/Server.zig");
const server_wasi = @import("runtime/server/wasm/entrypoint.zig");
const client = @import("runtime/client/Client.zig").Client;
const Constant = @import("constant.zig");
const platform = @import("platform.zig").platform;
const sig = @import("util/sig.zig");
const zx_options = @import("zx_options");
pub const Config = @import("AppConfig.zig");

const is_dev = std.mem.eql(u8, zx_options.cli_command, "dev");

var g_stop_ctx: ?*anyopaque = null;
var g_stop_fn: ?*const fn (ctx: *anyopaque) void = null;

fn onShutdown() void {
    if (g_stop_fn) |f| if (g_stop_ctx) |ctx| {
        if (!is_dev) std.debug.print("\nShutting down...\n", .{});
        f(ctx);
    };
}

var debug_allocator: std.heap.DebugAllocator(.{ .stack_trace_frames = 100 }) = .{};
pub const allocator = switch (builtin.os.tag) {
    .wasi, .freestanding => std.heap.wasm_allocator,
    else => switch (builtin.mode) {
        .Debug => debug_allocator.allocator(),
        .ReleaseFast, .ReleaseSafe, .ReleaseSmall => std.heap.smp_allocator,
    },
};

const Io = if (platform.os == .freestanding) void else std.Io;

var threaded_instance: std.Io.Threaded = undefined;
var threaded_initialized = false;

pub fn io() Io {
    if (platform.os == .freestanding) return {};

    if (!threaded_initialized) {
        threaded_instance = std.Io.Threaded.init(allocator, .{});
        threaded_initialized = true;
    }
    return threaded_instance.io();
}

var kv_fs: zx.Kv.Fs = undefined;
var cache_fs: zx.Kv.Fs = undefined;

var g_datadir: ?[]const u8 = null;
var g_staticdir: ?[]const u8 = null;
var g_db_url: ?[]const u8 = null;

fn resolveOptions(alloc: std.mem.Allocator, init: zx.Init, config: Config) !Config {
    var resolved = config;

    const rootdir_env = envVar(alloc, init, "ZIEX_ROOT_DIR");
    const datadir_env = envVar(alloc, init, "ZIEX_DATA_DIR");
    const staticdir_env = envVar(alloc, init, "ZIEX_STATIC_DIR");
    const rootdir = rootdir_env orelse Constant.default_rootdir;
    defer if (rootdir_env) |s| alloc.free(s);
    defer if (datadir_env) |s| alloc.free(s);
    defer if (staticdir_env) |s| alloc.free(s);

    const datadir = try std.fs.path.join(alloc, &.{ rootdir, datadir_env orelse Constant.default_datadir });
    const staticdir = try std.fs.path.join(alloc, &.{ rootdir, staticdir_env orelse Constant.default_staticdir });

    resolved.datadir = datadir;
    resolved.staticdir = staticdir;

    switch (platform.os) {
        .freestanding, .wasi => |os| {
            if (os == .wasi) zx.db = try zx.Db.Wasm.open(null, null, "default", .{});

            var kv_wasm = zx.Kv.Wasm{};
            zx.kv = kv_wasm.kv();

            return resolved;
        },
        else => {},
    }

    const kv_subdir = try std.fs.path.join(alloc, &.{ datadir, "kv" });
    const cache_subdir = try std.fs.path.join(alloc, &.{ datadir, "cache" });
    const db_dir = try std.fs.path.join(alloc, &.{ datadir, "db", "default.db" });
    defer alloc.free(db_dir);
    const db_url = try std.fmt.allocPrint(alloc, "file:{s}", .{db_dir});

    kv_fs = .{ .io = init.io, .subdir = kv_subdir };
    cache_fs = .{ .io = init.io, .subdir = cache_subdir };

    zx.kv = kv_fs.kv();
    zx.cache = try zx.Cache.init(init.io, alloc, cache_fs.kv(), .{
        .max_size = resolved.cache.max_size,
    });

    zx.db = try zx.Db.Sqlite.open(alloc, init.io, db_url, .{});

    g_datadir = datadir;
    g_staticdir = staticdir;
    g_db_url = db_url;

    return resolved;
}

fn cleanupOptions(alloc: std.mem.Allocator) void {
    if (g_datadir == null) return;
    zx.db.deinit();
    zx.cache.deinit();
    if (g_db_url) |s| alloc.free(s);
    if (cache_fs.subdir.len > 0) alloc.free(cache_fs.subdir);
    if (kv_fs.subdir.len > 0) alloc.free(kv_fs.subdir);
    if (g_staticdir) |s| alloc.free(s);
    if (g_datadir) |s| alloc.free(s);
    g_datadir = null;
    g_staticdir = null;
    g_db_url = null;
}

fn envVar(alloc: std.mem.Allocator, init: zx.Init, name: []const u8) ?[]const u8 {
    if (platform.os == .freestanding or platform.os == .wasi) return null;
    const minimal: std.process.Init.Minimal = switch (@TypeOf(init)) {
        std.process.Init.Minimal => init,
        std.process.Init => init.minimal,
        else => return null,
    };
    return minimal.environ.getAlloc(alloc, name) catch null;
}

pub fn App(comptime H: type) type {
    return AppInstance(H);
}

fn AppInstance(comptime H: type) type {
    const Instance = switch (platform.role) {
        .client => void,
        .server => switch (platform.os) {
            .wasi => void,
            else => *server.Server(H),
        },
    };

    return struct {
        const Self = @This();

        instance: Instance,
        io: ?std.Io,
        inita: zx.Init,
        alloc: std.mem.Allocator,

        pub fn init(inita: zx.Init, process_io: anytype, alloc: std.mem.Allocator, config: Config, app_ctx: H) !Self {
            const resolved = try resolveOptions(alloc, inita, config);

            const instance: Instance = switch (platform.role) {
                .client => {},
                .server => switch (platform.os) {
                    .wasi => {},
                    else => try server.Server(H).init(
                        if (@TypeOf(process_io) == std.Io) process_io else return error.InvalidIo,
                        alloc,
                        resolved,
                        app_ctx,
                    ),
                },
            };

            if (platform.role == .server and platform.os != .wasi) instance.info();

            return .{
                .instance = instance,
                .io = if (@TypeOf(process_io) == std.Io) process_io else null,
                .inita = inita,
                .alloc = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            if (platform.role == .server and platform.os != .wasi) self.instance.deinit();
            if (platform.os != .wasi and platform.os != .freestanding) cleanupOptions(self.alloc);
            if (platform.os != .freestanding and threaded_initialized) {
                threaded_instance.deinit();
                threaded_initialized = false;
            }
            if (builtin.mode == .Debug and platform.os != .freestanding)
                std.debug.assert(debug_allocator.deinit() == .ok);
        }

        pub fn start(self: Self) !void {
            switch (platform.role) {
                .client => try client.run(),
                .server => switch (platform.os) {
                    .wasi => try server_wasi.run(self.inita),
                    else => {
                        // Only wire up graceful shutdown in debug builds.
                        if (comptime builtin.mode == .Debug) {
                            const stopFn = struct {
                                fn call(ctx: *anyopaque) void {
                                    const s: *server.Server(H) = @ptrCast(@alignCast(ctx));
                                    s.stop();
                                }
                            }.call;
                            g_stop_ctx = self.instance;
                            g_stop_fn = stopFn;
                            sig.register(onShutdown);
                        }
                        defer {
                            if (comptime builtin.mode == .Debug) {
                                sig.unregister();
                                g_stop_ctx = null;
                                g_stop_fn = null;
                            }
                        }
                        try self.instance.start();
                    },
                },
            }
        }
    };
}
