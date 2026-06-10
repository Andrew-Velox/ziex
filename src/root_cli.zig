// -- Core Language --//
const core = @import("core_lang");

pub const Ast = core.Ast;
pub const Parse = core.Parse;
pub const Validate = core.Validate;
pub const sourcemap = core.sourcemap;

pub const info = @import("zx_info");

// --- Platform --- //
const plfm = @import("platform.zig");

pub const Platform = plfm.Platform;
pub const platform: Platform = plfm.platform;

// --- Options --- //
pub const StaticParam = @import("options.zig").StaticParam;

// --- Namespaces --- //
const srv = @import("runtime/server/Server.zig");
pub const server = struct {
    pub const SerilizableAppMeta = srv.SerilizableAppMeta;
    pub const ServerMeta = srv.ServerMeta;
};
