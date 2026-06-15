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

const feature_sqlite_server = zx_options.feature_sqlite_server;
const feature_kv_server = zx_options.feature_kv_server;
const feature_kv_client = zx_options.feature_kv_client;
const feature_cache_server = zx_options.feature_cache_server;

var kv: zx.Kv = undefined;
var cache: zx.Cache = undefined;
var db: zx.Db = undefined;

var kv_fs: if (feature_kv_server) zx.Kv.Fs else void = undefined;
var cache_fs: if (feature_cache_server) zx.Kv.Fs else void = undefined;

var g_datadir: ?[]const u8 = null;
var g_staticdir: ?[]const u8 = null;
var g_db_url: ?[]const u8 = null;
var g_kv_subdir: ?[]const u8 = null;
var g_cache_subdir: ?[]const u8 = null;

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
            // freestanding => client (browser wasm); wasi => server (server wasm).
            const wasm_kv_enabled = switch (os) {
                .wasi => feature_kv_server,
                else => feature_kv_client,
            };

            // Feature ==> zx.db (wasm backend, server-side only)
            if (comptime feature_sqlite_server) {
                if (os == .wasi) zx.db = try zx.Db.Wasm.open(null, null, "default", .{});
            }

            // Feature ==> zx.kv (wasm backend)
            if (comptime wasm_kv_enabled) {
                var kv_wasm = zx.Kv.Wasm{};
                zx.kv = kv_wasm.kv();
            }

            return resolved;
        },
        else => {},
    }

    // Native target is always server-side from here on.

    // Feature ==> zx.kv (filesystem backend)
    if (comptime feature_kv_server) {
        const kv_subdir = try std.fs.path.join(alloc, &.{ datadir, "kv" });
        kv_fs = .{ .io = init.io, .subdir = kv_subdir };
        kv = kv_fs.kv();
        zx.kv = kv;
        g_kv_subdir = kv_subdir;
    }

    // Feature ==> zx.cache (filesystem backend)
    if (comptime feature_cache_server) {
        const cache_subdir = try std.fs.path.join(alloc, &.{ datadir, "cache" });
        cache_fs = .{ .io = init.io, .subdir = cache_subdir };
        const cache_kv: zx.Kv = cache_fs.kv();
        cache = try zx.Cache.init(init.io, alloc, cache_kv, .{
            .max_size = resolved.cache.max_size,
        });
        g_cache_subdir = cache_subdir;
    }

    // Feature ==> zx.db (sqlite backend)
    if (comptime feature_sqlite_server) {
        const db_dir = try std.fs.path.join(alloc, &.{ datadir, "db", "default.db" });
        defer alloc.free(db_dir);
        const db_url = try std.fmt.allocPrint(alloc, "file:{s}", .{db_dir});
        zx.db = try zx.Db.Sqlite.open(alloc, init.io, db_url, .{});
        g_db_url = db_url;
    }

    g_datadir = datadir;
    g_staticdir = staticdir;

    return resolved;
}

fn cleanupOptions(alloc: std.mem.Allocator) void {
    if (g_datadir == null) return;

    // Feature ==> zx.db (sqlite backend)
    if (comptime feature_sqlite_server) {
        if (g_db_url) |s| {
            zx.db.deinit();
            alloc.free(s);
        }
    }

    // Feature ==> zx.cache
    if (comptime feature_cache_server) {
        if (g_cache_subdir) |s| {
            zx.cache.deinit();
            alloc.free(s);
        }
    }

    // Feature ==> zx.kv
    if (comptime feature_kv_server) {
        if (g_kv_subdir) |s| alloc.free(s);
    }

    if (g_staticdir) |s| alloc.free(s);
    if (g_datadir) |s| alloc.free(s);
    g_datadir = null;
    g_staticdir = null;
    g_db_url = null;
    g_kv_subdir = null;
    g_cache_subdir = null;
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
