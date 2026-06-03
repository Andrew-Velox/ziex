pub const Cache = @This();

const std = @import("std");
const builtin = @import("builtin");
const cachez = if (builtin.cpu.arch.isWasm())
    // This is for satisfying Playground in which we don't have 'cachez' dep available.
    cachez_failing
else
    @import("cachez");

const zx = @import("../../root.zig");

const Allocator = std.mem.Allocator;
const Kv = zx.Kv;

const entry_version: u8 = 1;
const header_len = 9;

backend: Kv = Kv.failing,
namespace: []const u8 = "default",

pub const PutOptions = Kv.PutOptions;

pub const Config = struct {
    max_size: u32 = 8000,
    segment_count: u16 = 8,
    gets_per_promote: u8 = 5,
    shrink_ratio: f32 = 0.2,
};

const CacheEntry = struct {
    bytes: []u8,

    pub fn removedFromCache(self: CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }
};

const State = struct {
    io: std.Io,
    allocator: Allocator,
    memory: cachez.Cache(CacheEntry),
};

const StoredEntry = struct {
    expires_at: ?u64,
    payload: []const u8,
};

const StateMutex = struct {
    inner: std.Io.Mutex = .init,
    pub fn lock(self: *@This(), io: std.Io) void {
        self.inner.lockUncancelable(io);
    }
    pub fn unlock(self: *@This(), io: std.Io) void {
        self.inner.unlock(io);
    }
};

var state: ?State = null;
var state_mutex: StateMutex = .{};

pub fn init(io: std.Io, kv: Kv, config: Config) !Cache {
    const cachez_config = cachez.Config{
        .max_size = config.max_size,
        .segment_count = config.segment_count,
        .gets_per_promote = config.gets_per_promote,
        .shrink_ratio = config.shrink_ratio,
    };

    const lock_io = if (state) |current| current.io else io;
    state_mutex.lock(lock_io);
    defer state_mutex.unlock(lock_io);

    if (state) |*current| {
        current.memory.deinit();
        state = null;
    }

    state = .{
        .io = io,
        .allocator = zx.allocator,
        .memory = try cachez.Cache(CacheEntry).init(io, zx.allocator, cachez_config),
    };

    return .{
        .backend = kv,
        .namespace = "default",
    };
}

/// Deinitialize the cache
pub fn deinit(_: *Cache) void {
    const io = if (state) |current| current.io else return;
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    if (state) |*current| {
        current.memory.deinit();
        state = null;
    }
}

pub fn scoped(self: Cache, comptime ns: @EnumLiteral()) Cache {
    return .{
        .backend = self.backend,
        .namespace = @tagName(ns),
    };
}

pub fn scope(self: Cache, comptime ns: @EnumLiteral()) Cache {
    return self.scoped(ns);
}

/// The persistent backend bound to this handle's namespace.
fn boundBackend(self: Cache) Kv {
    return .{
        .vtable = self.backend.vtable,
        .userdata = self.backend.userdata,
        .namespace = if (self.namespace.len == 0) "default" else self.namespace,
    };
}

pub fn get(self: Cache, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
    const io = if (state) |current| current.io else return null;
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    const s = if (state) |*current| current else return null;
    const scoped_key = try scopedKey(s.allocator, self.namespace, key);
    defer s.allocator.free(scoped_key);

    if (s.memory.get(scoped_key)) |entry| {
        defer entry.release();
        return @as(?[]u8, try allocator.dupe(u8, entry.value.bytes));
    }

    const backend = self.boundBackend();
    const encoded = (try backend.get(s.allocator, key)) orelse return null;
    defer s.allocator.free(encoded);

    const decoded = try decodeStoredEntry(encoded);
    if (isExpired(s.io, decoded.expires_at)) {
        try backend.delete(key);
        return null;
    }

    putMemoryEntryLocked(s, scoped_key, decoded.payload, ttlFromExpiration(s.io, decoded.expires_at)) catch {};
    return @as(?[]u8, try allocator.dupe(u8, decoded.payload));
}

pub fn as(self: Cache, allocator: std.mem.Allocator, key: []const u8, comptime T: type) !?T {
    const raw = (try self.get(allocator, key)) orelse return null;
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

pub fn put(self: Cache, key: []const u8, value: []const u8, opts: PutOptions) !void {
    const io = if (state) |current| current.io else return;
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    const s = if (state) |*current| current else return;
    const encoded = try encodeStoredEntry(s.io, s.allocator, value, opts);
    defer s.allocator.free(encoded);

    try self.boundBackend().put(key, encoded, .{});

    const scoped_key = try scopedKey(s.allocator, self.namespace, key);
    defer s.allocator.free(scoped_key);
    try putMemoryEntryLocked(s, scoped_key, value, ttlFromOptions(s.io, opts));
}

pub fn putAs(self: Cache, key: []const u8, value: anytype, opts: PutOptions) !void {
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

    try self.put(key, writer.written(), opts);
}

pub fn delete(self: Cache, key: []const u8) !void {
    const io = if (state) |current| current.io else return;
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    const s = if (state) |*current| current else return;
    const scoped_key = try scopedKey(s.allocator, self.namespace, key);
    defer s.allocator.free(scoped_key);

    _ = s.memory.del(scoped_key);
    try self.boundBackend().delete(key);
}

pub fn list(self: Cache, allocator: std.mem.Allocator, prefix: []const u8) ![][]u8 {
    const io = if (state) |current| current.io else return &[_][]u8{};
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    const s = if (state) |*current| current else return &[_][]u8{};
    const backend = self.boundBackend();
    const keys = try backend.list(s.allocator, prefix);
    defer {
        for (keys) |key| s.allocator.free(key);
        s.allocator.free(keys);
    }

    var live_keys: std.ArrayList([]u8) = .empty;
    defer live_keys.deinit(allocator);

    for (keys) |key| {
        const encoded = (try backend.get(s.allocator, key)) orelse continue;
        defer s.allocator.free(encoded);

        const decoded = try decodeStoredEntry(encoded);
        if (isExpired(s.io, decoded.expires_at)) {
            try backend.delete(key);

            const scoped_key = try scopedKey(s.allocator, self.namespace, key);
            defer s.allocator.free(scoped_key);
            _ = s.memory.del(scoped_key);
            continue;
        }

        try live_keys.append(allocator, try allocator.dupe(u8, key));
    }

    return live_keys.toOwnedSlice(allocator);
}

pub fn del(self: Cache, key: []const u8) bool {
    const io = if (state) |current| current.io else return false;
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    const s = if (state) |*current| current else return false;
    const backend = self.boundBackend();
    const existing = backend.get(s.allocator, key) catch null;
    const existed = if (existing) |bytes| blk: {
        s.allocator.free(bytes);
        break :blk true;
    } else false;

    const scoped_key = scopedKey(s.allocator, self.namespace, key) catch return existed;
    defer s.allocator.free(scoped_key);

    const memory_deleted = s.memory.del(scoped_key);
    backend.delete(key) catch {};
    return existed or memory_deleted;
}

pub fn delPrefix(self: Cache, prefix: []const u8) !usize {
    const io = if (state) |current| current.io else return 0;
    state_mutex.lock(io);
    defer state_mutex.unlock(io);

    const s = if (state) |*current| current else return 0;
    const backend = self.boundBackend();
    const keys = try backend.list(s.allocator, prefix);
    defer {
        for (keys) |key| s.allocator.free(key);
        s.allocator.free(keys);
    }

    var deleted: usize = 0;
    for (keys) |key| {
        try backend.delete(key);

        const scoped_key = try scopedKey(s.allocator, self.namespace, key);
        defer s.allocator.free(scoped_key);
        _ = s.memory.del(scoped_key);
        deleted += 1;
    }

    return deleted;
}

fn scopedKey(allocator: Allocator, ns: []const u8, key: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\x1f{s}", .{ ns, key });
}

fn encodeStoredEntry(io: std.Io, allocator: Allocator, payload: []const u8, opts: PutOptions) ![]u8 {
    const expires_at = try expirationFromOptions(io, opts);
    const encoded = try allocator.alloc(u8, header_len + payload.len);
    encoded[0] = entry_version;
    std.mem.writeInt(u64, encoded[1..header_len], expires_at orelse 0, .little);
    @memcpy(encoded[header_len..], payload);
    return encoded;
}

fn decodeStoredEntry(encoded: []const u8) !StoredEntry {
    if (encoded.len < header_len or encoded[0] != entry_version) return error.InvalidCacheEntry;

    const expires_raw = std.mem.readInt(u64, encoded[1..header_len], .little);
    return .{
        .expires_at = if (expires_raw == 0) null else expires_raw,
        .payload = encoded[header_len..],
    };
}

fn now(io: std.Io) u64 {
    if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .wasi) return 0;
    const ts = std.Io.Timestamp.now(io, .real);
    return @as(u64, @intCast(@divTrunc(ts.nanoseconds, 1_000_000_000)));
}

fn expirationFromOptions(io: std.Io, opts: PutOptions) !?u64 {
    if (opts.expiration) |expiration| return expiration;
    if (opts.expiration_ttl) |ttl| {
        return now(io) + ttl;
    }
    return null;
}

fn ttlFromOptions(io: std.Io, opts: PutOptions) ?u32 {
    if (opts.expiration_ttl) |ttl| return clampTtl(ttl);
    if (opts.expiration) |expiration| return ttlFromExpiration(io, expiration);
    return null;
}

fn ttlFromExpiration(io: std.Io, expires_at: ?u64) ?u32 {
    const expiration = expires_at orelse return null;
    const current_now = now(io);
    if (expiration <= current_now) return 0;
    return clampTtl(expiration - current_now);
}

fn clampTtl(ttl: u64) u32 {
    return std.math.cast(u32, ttl) orelse std.math.maxInt(u32);
}

fn isExpired(io: std.Io, expires_at: ?u64) bool {
    const expiration = expires_at orelse return false;
    return expiration <= now(io);
}

fn putMemoryEntryLocked(s: *State, scoped_key: []const u8, value: []const u8, ttl_seconds: ?u32) !void {
    const value_copy = try s.allocator.dupe(u8, value);
    errdefer s.allocator.free(value_copy);

    try s.memory.put(scoped_key, .{ .bytes = value_copy }, .{
        .ttl = cachezSafeTtl(s.io, ttl_seconds),
    });
}

fn cachezSafeTtl(io: std.Io, ttl_seconds: ?u32) u32 {
    const current_now = now(io);
    const max_u32 = std.math.maxInt(u32);
    if (current_now >= max_u32) return 0;

    const max_ttl = max_u32 - @as(u32, @intCast(current_now));
    return @min(ttl_seconds orelse max_ttl, max_ttl);
}

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

pub const failing: Cache = .{
    .backend = Kv.failing,
};

const cachez_failing = struct {
    pub const PutConfig = struct {
        ttl: u32 = 300,
        size: u32 = 1,
    };

    pub fn Cache(comptime T: type) type {
        return struct {
            allocator: Allocator,

            const Self = @This();

            pub fn init(io: std.Io, allocator: Allocator, _: Config) !Self {
                _ = io;
                return .{
                    .allocator = allocator,
                };
            }

            pub fn deinit(_: *Self) void {}

            pub fn contains(self: *const Self, key: []const u8) bool {
                _ = key;
                _ = self;
                return false;
            }

            pub fn get(self: *Self, key: []const u8) ?*Entry(T) {
                _ = key;
                _ = self;
                return null;
            }

            pub fn getEntry(self: *const Self, key: []const u8) ?*Entry(T) {
                _ = key;
                _ = self;
                return null;
            }

            pub fn put(self: *Self, key: []const u8, value: T, config: PutConfig) !void {
                _ = key;
                _ = value;
                _ = config;
                _ = self;
            }

            pub fn del(self: *Self, key: []const u8) bool {
                _ = key;
                _ = self;
                return false;
            }

            pub fn delPrefix(self: *Self, prefix: []const u8) !usize {
                _ = prefix;
                _ = self;
                return 0;
            }

            pub fn fetch(self: *Self, comptime S: type, key: []const u8, loader: *const fn (loader_state: S, key: []const u8) anyerror!?T, loader_state: S, config: PutConfig) !?*Entry(T) {
                _ = key;
                _ = loader;
                _ = loader_state;
                _ = config;
                _ = self;
                return null;
            }

            pub fn maxSize(self: Self) usize {
                _ = self;
                return 0;
            }
        };
    }

    pub fn Entry(comptime T: type) type {
        return struct {
            key: []const u8,
            value: T,
            expires: u32,

            const Self = @This();

            pub fn init(allocator: Allocator, key: []const u8, value: T, size: u32, expires: u32) Self {
                _ = allocator;
                _ = size;
                return .{
                    .key = key,
                    .value = value,
                    .expires = expires,
                };
            }

            pub fn expired(self: *Self) bool {
                return self.ttl() <= 0;
            }

            pub fn ttl(self: *Self) i64 {
                _ = self;
                return 0;
            }

            pub fn hit(self: *Self) u8 {
                _ = self;
                return 0;
            }

            pub fn borrow(self: *Self) void {
                _ = self;
            }

            pub fn release(self: *Self) void {
                _ = self;
            }
        };
    }
};
