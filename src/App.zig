const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig").platform;
const server = @import("runtime/server/Server.zig");
const server_wasi = @import("runtime/server/wasm/entrypoint.zig");
const client = @import("runtime/client/Client.zig").Client;
const zx = @import("root.zig");

pub const Config = @import("AppConfig.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .{};
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

fn resolveOptions(init: zx.Init, config: Config) !Config {
    const zx_options = @import("zx_options"); // Remove and from build system pass these as env var

    var resolved = config;

    const datadir = config.datadir orelse envVar(init, "ZX_DATADIR") orelse zx_options.datadir;
    const staticdir = config.staticdir orelse envVar(init, "ZX_STATICDIR") orelse zx_options.staticdir;

    resolved.datadir = datadir;
    resolved.staticdir = staticdir;

    if (platform.os == .freestanding or platform.os == .wasi) {
        var kv_wasm = zx.Kv.Wasm{};
        zx.kv = kv_wasm.kv();

        return resolved;
    }

    const arena = init.arena.allocator();

    kv_fs = .{
        .io = init.io,
        .subdir = try std.fs.path.join(arena, &.{ datadir, "kv" }),
    };
    cache_fs = .{
        .io = init.io,
        .subdir = try std.fs.path.join(arena, &.{ datadir, "cache" }),
    };

    zx.kv = kv_fs.kv();
    zx.cache = try zx.Cache.init(init.io, allocator, cache_fs.kv(), .{
        .max_size = resolved.cache.max_size,
    });

    return resolved;
}

fn envVar(init: zx.Init, name: []const u8) ?[]const u8 {
    const minimal: std.process.Init.Minimal = switch (@TypeOf(zx.Init)) {
        std.process.Init.Minimal => init,
        std.process.Init => init.minimal,
        else => return null,
    };
    return minimal.environ.getAlloc(minimal.gpa, name) catch null;
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

        pub fn init(inita: zx.Init, process_io: anytype, alloc: std.mem.Allocator, config: Config, app_ctx: H) !Self {
            const resolved = try resolveOptions(inita, config);

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
            };
        }

        pub fn deinit(self: *Self) void {
            if (platform.role == .server and platform.os != .wasi) self.instance.deinit();
            if (builtin.mode == .Debug and platform.os != .freestanding)
                std.debug.assert(debug_allocator.deinit() == .ok);
        }

        pub fn start(self: Self) !void {
            switch (platform.role) {
                .client => try client.run(),
                .server => switch (platform.os) {
                    .wasi => try server_wasi.run(self.inita),
                    else => try self.instance.start(),
                },
            }
        }
    };
}
