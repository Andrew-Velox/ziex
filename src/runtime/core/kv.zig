/// A Key Value store
///
/// Use this to store small pieces of data that need to be shared across requests or persisted across restarts.
///
/// The default zx.kv implementation is a native filesystem based store,
/// stored inside configurable datadir/kv/
///
/// Builtin bindings are provided for WASI for
///
/// - Cloudflare: Workers KV
///
/// and you can implement your own bindings or storage backends if desired.
pub const Kv = @This();

const std = @import("std");
const builtin = @import("builtin");
const zx_options = @import("zx_options");

const zx = @import("../../root.zig");
const kv_wasm = @import("../server/wasm/kv.zig");

userdata: ?*anyopaque = null,
vtable: *const VTable,

pub const VTable = struct {
    get: *const fn (userdata: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) anyerror!?[]u8,
    put: *const fn (userdata: ?*anyopaque, ns: []const u8, key: []const u8, value: []const u8, opts: PutOptions) anyerror!void,
    delete: *const fn (userdata: ?*anyopaque, ns: []const u8, key: []const u8) anyerror!void,
    list: *const fn (userdata: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) anyerror![][]u8,
};

pub const PutOptions = struct {
    expiration: ?u64 = null,
    expiration_ttl: ?u64 = null,
};

pub fn get(self: Kv, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    return self.vtable.get(self.userdata, "default", allocator, key);
}

/// Get the value of a key parsed as the given type, returning error if type is not expected.
pub fn as(self: Kv, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    return self.getTyped("default", allocator, key, T);
}

pub fn put(self: Kv, key: []const u8, value: []const u8, opts: PutOptions) !void {
    return self.vtable.put(self.userdata, "default", key, value, opts);
}

pub fn putAs(self: Kv, key: []const u8, value: anytype, opts: PutOptions) !void {
    return self.putTyped("default", key, value, opts);
}

pub fn delete(self: Kv, key: []const u8) !void {
    return self.vtable.delete(self.userdata, "default", key);
}

pub fn list(self: Kv, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    return self.vtable.list(self.userdata, "default", allocator, prefix);
}

/// Return a scoped handle that routes all operations to the named KV binding.
///
/// ```zig
/// const users = zx.kv.scope("users");
/// const val = try users.get(ctx.arena, "user-123");
/// ```
pub fn scope(self: Kv, ns: []const u8) Scope {
    return .{ .kv = self, .ns = ns };
}

const Scope = struct {
    kv: Kv,
    ns: []const u8,

    pub fn get(self: Scope, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        return self.kv.vtable.get(self.kv.userdata, self.ns, allocator, key);
    }

    pub fn as(self: Scope, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
        return self.kv.getTyped(self.ns, allocator, key, T);
    }

    pub fn put(self: Scope, key: []const u8, value: []const u8, opts: PutOptions) !void {
        return self.kv.vtable.put(self.kv.userdata, self.ns, key, value, opts);
    }

    pub fn putAs(self: Scope, key: []const u8, value: anytype, opts: PutOptions) !void {
        return self.kv.putTyped(self.ns, key, value, opts);
    }

    pub fn delete(self: Scope, key: []const u8) !void {
        return self.kv.vtable.delete(self.kv.userdata, self.ns, key);
    }

    pub fn list(self: Scope, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
        return self.kv.vtable.list(self.kv.userdata, self.ns, allocator, prefix);
    }
};

fn getTyped(self: Kv, ns: []const u8, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    const raw = (try self.vtable.get(self.userdata, ns, allocator, key)) orelse return null;
    defer allocator.free(raw);

    const expected_hash = zx.util.zxon.schema(T).hash;
    if (try storedTypeHash(raw) != expected_hash) return error.InvalidType;

    const TypedValue = struct {
        hash: u64,
        value: T,
    };

    const parsed = try zx.util.zxon.parse(TypedValue, allocator, raw, .{});
    return parsed.value;
}

fn putTyped(self: Kv, ns: []const u8, key: []const u8, value: anytype, opts: PutOptions) !void {
    const ValueType = @TypeOf(value);
    const TypedValue = struct {
        hash: u64,
        value: ValueType,
    };

    var writer = std.Io.Writer.Allocating.init(zx.allocator);
    defer writer.deinit();

    try zx.util.zxon.serialize(TypedValue{
        .hash = zx.util.zxon.schema(ValueType).hash,
        .value = value,
    }, &writer.writer, .{});

    return self.vtable.put(self.userdata, ns, key, writer.written(), opts);
}

// -- Default backend -- //

/// The platform default backend, used to initialize `zx.kv`. Platform adapters
/// reassign `zx.kv` at startup (before any request is served) to swap backends.
pub const default: Kv = if (builtin.cpu.arch == .wasm32)
    .{ .vtable = &noop_vtable }
else
    .{ .vtable = &filesystem_vtable };

fn storedTypeHash(raw: []const u8) !u64 {
    var i: usize = 0;

    while (i < raw.len and std.ascii.isWhitespace(raw[i])) : (i += 1) {}
    if (i >= raw.len or raw[i] != '[') return error.InvalidType;
    i += 1;

    while (i < raw.len and std.ascii.isWhitespace(raw[i])) : (i += 1) {}
    const start = i;

    while (i < raw.len and std.ascii.isDigit(raw[i])) : (i += 1) {}
    if (start == i) return error.InvalidType;

    return std.fmt.parseUnsigned(u64, raw[start..i], 10);
}

// -- Impl: Noop (WASM default - replaced by edge adapter at startup) -- //

fn noopGet(_: ?*anyopaque, _: []const u8, _: std.mem.Allocator, _: []const u8) anyerror!?[]u8 {
    return null;
}
fn noopPut(_: ?*anyopaque, _: []const u8, _: []const u8, _: []const u8, _: PutOptions) anyerror!void {}
fn noopDelete(_: ?*anyopaque, _: []const u8, _: []const u8) anyerror!void {}
fn noopList(_: ?*anyopaque, _: []const u8, _: std.mem.Allocator, _: []const u8) anyerror![][]u8 {
    return &[_][]u8{};
}

const noop_vtable = VTable{
    .get = &noopGet,
    .put = &noopPut,
    .delete = &noopDelete,
    .list = &noopList,
};

// -- Impl: Filesystem (native default - persists to datadir/kv/<ns>/) -- //
const kv_store_base = zx_options.datadir ++ std.fs.path.sep_str ++ "kv";

fn keyPath(ns: []const u8, key: []const u8, buf: *[1024]u8) ?[]u8 {
    const encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(key.len);
    // "<base>/<ns>/<encoded_key>"
    const needed = kv_store_base.len + 1 + ns.len + 1 + encoded_len;
    if (needed > buf.len) return null;
    var pos: usize = 0;
    @memcpy(buf[pos..][0..kv_store_base.len], kv_store_base);
    pos += kv_store_base.len;
    buf[pos] = std.fs.path.sep;
    pos += 1;
    @memcpy(buf[pos..][0..ns.len], ns);
    pos += ns.len;
    buf[pos] = std.fs.path.sep;
    pos += 1;
    const encoded = std.base64.url_safe_no_pad.Encoder.encode(buf[pos..], key);
    return buf[0 .. pos + encoded.len];
}

fn nsDir(ns: []const u8, buf: *[256]u8) ?[]u8 {
    const needed = kv_store_base.len + 1 + ns.len;
    if (needed > buf.len) return null;
    @memcpy(buf[0..kv_store_base.len], kv_store_base);
    buf[kv_store_base.len] = std.fs.path.sep;
    @memcpy(buf[kv_store_base.len + 1 ..][0..ns.len], ns);
    return buf[0..needed];
}

fn fsGet(_: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var buf: [1024]u8 = undefined;
    const path = keyPath(ns, key, &buf) orelse return null;
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(10 * 1024 * 1024)) catch null;
}

fn fsPut(_: ?*anyopaque, ns: []const u8, key: []const u8, value: []const u8, _: PutOptions) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    var buf: [1024]u8 = undefined;
    const path = keyPath(ns, key, &buf) orelse return error.KeyTooLong;
    var file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, value);
    try file.replace(io);
}

fn fsDelete(_: ?*anyopaque, ns: []const u8, key: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    var buf: [1024]u8 = undefined;
    const path = keyPath(ns, key, &buf) orelse return;
    std.Io.Dir.cwd().deleteFile(io, path) catch {};
}

fn fsList(_: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir_buf: [256]u8 = undefined;
    const dir_path = nsDir(ns, &dir_buf) orelse return &[_][]u8{};
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return &[_][]u8{};
    defer dir.close(io);
    var keys = std.ArrayList([]u8).empty;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const decoded_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(entry.name) catch continue;
        const key = try allocator.alloc(u8, decoded_len);
        errdefer allocator.free(key);
        std.base64.url_safe_no_pad.Decoder.decode(key, entry.name) catch {
            allocator.free(key);
            continue;
        };
        if (prefix.len == 0 or std.mem.startsWith(u8, key, prefix)) {
            try keys.append(allocator, key);
        } else {
            allocator.free(key);
        }
    }
    return keys.toOwnedSlice(allocator);
}

const filesystem_vtable = VTable{
    .get = &fsGet,
    .put = &fsPut,
    .delete = &fsDelete,
    .list = &fsList,
};
