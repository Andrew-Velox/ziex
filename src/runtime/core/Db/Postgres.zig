const Postgres = @This();

const std = @import("std");
const Db = @import("../Db.zig");

allocator: std.mem.Allocator,

pub const OpenOptions = struct {
    readonly: bool = false,
    create: bool = true,
    max_pool_size: usize = 5,

    host: ?[]const u8 = null,
    port: u16 = 5432,
    user: ?[]const u8 = null,
    password: ?[]const u8 = null,
    database: ?[]const u8 = null,
    sslmode: SslMode = .prefer,
    connect_timeout_ms: u32 = 10_000,

    pub const SslMode = enum { disable, prefer, require, verify_full };

    pub fn fromNeutral(neutral: Db.OpenOptions) OpenOptions {
        return .{
            .readonly = neutral.readonly,
            .create = neutral.create,
            .max_pool_size = neutral.max_pool_size,
        };
    }
};

pub fn open(allocator: std.mem.Allocator, io: std.Io, url: ?[]const u8, options: anytype) !Db {
    _ = allocator;
    _ = io;
    _ = url;
    _ = normalizeOptions(options);
    return Db.DbError.Unsupported;
}

fn normalizeOptions(options: anytype) OpenOptions {
    const T = @TypeOf(options);
    if (T == OpenOptions) return options;
    if (T == Db.OpenOptions) return OpenOptions.fromNeutral(options);
    if (@typeInfo(T) == .@"struct") return options;
    @compileError("Postgres.open expects Postgres.OpenOptions or Db.OpenOptions, got " ++ @typeName(T));
}

pub fn db(self: *Postgres) Db {
    return .{ .userdata = self, .vtable = &database_vtable };
}

pub fn from(database: Db) !*Postgres {
    if (database.vtable != &database_vtable) return Db.DbError.WrongBackend;
    return @ptrCast(@alignCast(database.userdata orelse return Db.DbError.InvalidState));
}

fn prepare(_: ?*anyopaque, _: []const u8) !Db.Statement {
    return Db.DbError.Unsupported;
}
fn run(_: ?*anyopaque, _: []const u8, _: Db.Bindings) !Db.RunResult {
    return Db.DbError.Unsupported;
}
fn transaction(_: ?*anyopaque, _: Db.TransactionMode, _: *anyopaque, _: Db.TransactionCallback) !void {
    return Db.DbError.Unsupported;
}
fn close(_: ?*anyopaque, _: bool) !void {
    return;
}
fn stmtAll(_: ?*anyopaque, _: std.mem.Allocator, _: Db.Bindings) ![]const Db.Row {
    return Db.DbError.Unsupported;
}
fn stmtGet(_: ?*anyopaque, _: std.mem.Allocator, _: Db.Bindings) !?Db.Row {
    return Db.DbError.Unsupported;
}
fn stmtRun(_: ?*anyopaque, _: Db.Bindings) !Db.RunResult {
    return Db.DbError.Unsupported;
}
fn stmtValues(_: ?*anyopaque, _: std.mem.Allocator, _: Db.Bindings) ![]const []const Db.Value {
    return Db.DbError.Unsupported;
}
fn stmtIterate(_: ?*anyopaque, _: Db.Bindings) !Db.Statement.Iterator {
    return Db.DbError.Unsupported;
}
fn stmtFinalize(_: ?*anyopaque) void {}
fn stmtToString(_: ?*anyopaque, _: std.mem.Allocator) ![]u8 {
    return Db.DbError.Unsupported;
}
fn stmtColumnNames(_: ?*anyopaque) []const []const u8 {
    return &.{};
}
fn stmtColumnTypes(_: ?*anyopaque) []const Db.ColumnType {
    return &.{};
}
fn stmtParamsCount(_: ?*anyopaque) usize {
    return 0;
}

const database_vtable = Db.VTable{
    .prepare = &prepare,
    .run = &run,
    .transaction = &transaction,
    .close = &close,
    .stmtAll = &stmtAll,
    .stmtGet = &stmtGet,
    .stmtRun = &stmtRun,
    .stmtValues = &stmtValues,
    .stmtIterate = &stmtIterate,
    .stmtFinalize = &stmtFinalize,
    .stmtToString = &stmtToString,
    .stmtColumnNames = &stmtColumnNames,
    .stmtColumnTypes = &stmtColumnTypes,
    .stmtParamsCount = &stmtParamsCount,
};
