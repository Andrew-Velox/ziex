pub const Fs = @This();

const std = @import("std");
const builtin = @import("builtin");
const zx = @import("../../../root.zig");

const Kv = zx.Kv;

io: std.Io,
namespace: []const u8 = "default",
subdir: []const u8,

fn get(userdata: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const f: *Fs = @ptrCast(@alignCast(userdata));
    var buf: [1024]u8 = undefined;
    const path = keyPath(f.subdir, ns, key, &buf) orelse return null;
    return std.Io.Dir.cwd().readFileAlloc(f.io, path, allocator, .limited(10 * 1024 * 1024)) catch null;
}

fn put(userdata: ?*anyopaque, ns: []const u8, key: []const u8, value: []const u8, _: Kv.PutOptions) !void {
    const f: *Fs = @ptrCast(@alignCast(userdata));
    var buf: [1024]u8 = undefined;
    const path = keyPath(f.subdir, ns, key, &buf) orelse return error.KeyTooLong;
    var file = try std.Io.Dir.cwd().createFileAtomic(f.io, path, .{
        .make_path = true,
        .replace = true,
    });
    defer file.deinit(f.io);
    try file.file.writeStreamingAll(f.io, value);
    try file.replace(f.io);
}

fn delete(userdata: ?*anyopaque, ns: []const u8, key: []const u8) !void {
    const f: *Fs = @ptrCast(@alignCast(userdata));
    var buf: [1024]u8 = undefined;
    const path = keyPath(f.subdir, ns, key, &buf) orelse return;
    std.Io.Dir.cwd().deleteFile(f.io, path) catch {};
}

fn list(userdata: ?*anyopaque, ns: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    const f: *Fs = @ptrCast(@alignCast(userdata));
    var dir_buf: [256]u8 = undefined;
    const dir_path = nsDir(f.subdir, ns, &dir_buf) orelse return &[_][]u8{};
    var dir = std.Io.Dir.cwd().openDir(f.io, dir_path, .{ .iterate = true }) catch return &[_][]u8{};
    defer dir.close(f.io);
    var keys = std.ArrayList([]u8).empty;
    var iter = dir.iterate();
    while (try iter.next(f.io)) |entry| {
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

fn keyPath(base: []const u8, ns: []const u8, key: []const u8, buf: *[1024]u8) ?[]u8 {
    const encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(key.len);
    // "<base>/<ns>/<encoded_key>"
    const needed = base.len + 1 + ns.len + 1 + encoded_len;
    if (needed > buf.len) return null;
    var pos: usize = 0;
    @memcpy(buf[pos..][0..base.len], base);
    pos += base.len;
    buf[pos] = std.fs.path.sep;
    pos += 1;
    @memcpy(buf[pos..][0..ns.len], ns);
    pos += ns.len;
    buf[pos] = std.fs.path.sep;
    pos += 1;
    const encoded = std.base64.url_safe_no_pad.Encoder.encode(buf[pos..], key);
    return buf[0 .. pos + encoded.len];
}

fn nsDir(base: []const u8, ns: []const u8, buf: *[256]u8) ?[]u8 {
    const needed = base.len + 1 + ns.len;
    if (needed > buf.len) return null;
    @memcpy(buf[0..base.len], base);
    buf[base.len] = std.fs.path.sep;
    @memcpy(buf[base.len + 1 ..][0..ns.len], ns);
    return buf[0..needed];
}

pub fn kv(fs: *Fs) Kv {
    return Kv{
        .userdata = fs,
        .vtable = &.{
            .get = &get,
            .put = &put,
            .delete = &delete,
            .list = &list,
        },
    };
}
