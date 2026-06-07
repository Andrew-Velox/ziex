//! Embeds the canonical `_base` starter template so the `zx init` command can
//! materialize a new project. This file is rooted in `templates/` so that
//! `@embedFile` is permitted to read files under `_base/`. It is intentionally
//! kept outside `_base/` so it is never copied into generated user projects.

const base = "_base/";
const docker = "_docker/";

pub const TemplateFile = struct {
    pub const Name = enum { default, docker };

    name: ?Name = null,
    path: []const u8,
    content: []const u8,
};

pub const files = [_]TemplateFile{
    // Shared
    .{ .path = "build.zig.zon", .content = @embedFile(base ++ "build.zig.zon") },
    .{ .path = "build.zig", .content = @embedFile(base ++ "build.zig") },
    .{ .path = "app/main.zig", .content = @embedFile(base ++ "app/main.zig") },
    .{ .path = "README.md", .content = @embedFile(base ++ "README.md") },
    .{ .path = "app/assets/style.css", .content = @embedFile(base ++ "app/assets/style.css") },
    .{ .path = "app/public/favicon.ico", .content = @embedFile(base ++ "app/public/favicon.ico") },
    .{ .path = "app/pages/layout.zx", .content = @embedFile(base ++ "app/pages/layout.zx") },
    .{ .path = "app/pages/page.zx", .content = @embedFile(base ++ "app/pages/page.zx") },
    .{ .path = "app/pages/client.zx", .content = @embedFile(base ++ "app/pages/client.zx") },
    .{ .path = "app/pages/form/page.zx", .content = @embedFile(base ++ "app/pages/form/page.zx") },
    .{ .path = "app/pages/actions/page.zx", .content = @embedFile(base ++ "app/pages/actions/page.zx") },
    .{ .path = "app/pages/actions/client/page.zx", .content = @embedFile(base ++ "app/pages/actions/client/page.zx") },
    .{ .path = "app/pages/actions/server/page.zx", .content = @embedFile(base ++ "app/pages/actions/server/page.zx") },
    .{ .path = ".gitignore", .content = @embedFile(base ++ ".gitignore") },
    .{ .path = ".gitattributes", .content = @embedFile(base ++ ".gitattributes") },

    // Docker
    .{ .name = .docker, .path = "Dockerfile", .content = @embedFile(docker ++ "Dockerfile") },
    .{ .name = .docker, .path = "compose.yml", .content = @embedFile(docker ++ "compose.yml") },
    .{ .name = .docker, .path = ".dockerignore", .content = @embedFile(docker ++ ".dockerignore") },
};
