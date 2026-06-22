const Postgres = postgres.Create(Db);

const std = @import("std");
const postgres = @import("db_postgres");
const Db = @import("../Db.zig");

pub const OpenOptions = postgres.OpenOptions;
pub const open = postgres.open;
pub const db = postgres.db;
pub const from = postgres.from;
