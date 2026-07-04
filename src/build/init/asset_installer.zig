const std = @import("std");
const Manifest = @import("Build").Manifest;
const hashing = @import("hashing.zig");

/// Build helper: content-hash a static asset, install it, and upsert the
/// corresponding manifest injection (wasm preload link or jsglue script tag).
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    const src_path = args.next() orelse return error.MissingSrcPath;
    const dest_dir = args.next() orelse return error.MissingDestDir;
    const href_stem = args.next() orelse return error.MissingHrefStem;
    const manifest_path = args.next() orelse return error.MissingManifestPath;
    const file_stem = args.next() orelse "main";
    const file_ext = args.next() orelse ".wasm";
    const injection_kind = args.next() orelse "wasmlink";
    const clean_dest = std.mem.eql(u8, args.next() orelse "", "clean");

    const content = try std.Io.Dir.cwd().readFileAlloc(io, src_path, allocator, .unlimited);

    const hash_input = if (std.mem.eql(u8, file_ext, ".wasm"))
        try hashing.hashInput(allocator, content)
    else
        content;
    defer if (hash_input.ptr != content.ptr) allocator.free(hash_input);

    const hash_tag = hashing.contentTag(hash_input);

    if (std.fs.path.dirname(dest_dir)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }

    if (clean_dest) {
        try cleanGeneratedAssetsDir(io, dest_dir);
    }
    try std.Io.Dir.cwd().createDirPath(io, dest_dir);

    const dest_name = try std.fmt.allocPrint(allocator, "{s}.{s}{s}", .{ file_stem, &hash_tag, file_ext });
    const dest_path = try std.fs.path.join(allocator, &.{ dest_dir, dest_name });

    try std.Io.Dir.cwd().copyFile(src_path, std.Io.Dir.cwd(), dest_path, io, .{ .make_path = true });

    const href = try std.fmt.allocPrint(allocator, "{s}.{s}{s}", .{ href_stem, &hash_tag, file_ext });

    if (std.mem.eql(u8, injection_kind, "script")) {
        try Manifest.upsertJsglueInjection(io, allocator, manifest_path, .{
            .parent = .head,
            .position = .ending,
            .element = .{
                .tag = .script,
                .attributes = &.{
                    .{ .name = "defer" },
                    .{ .name = "src", .value = href },
                },
            },
        });
    } else {
        try Manifest.upsertWasmlinkInjection(io, allocator, manifest_path, .{
            .parent = .head,
            .position = .ending,
            .element = .{
                .tag = .link,
                .attributes = &.{
                    .{ .name = "id", .value = "__$wasmlink" },
                    .{ .name = "rel", .value = "preload" },
                    .{ .name = "as", .value = "fetch" },
                    .{ .name = "href", .value = href },
                    .{ .name = "crossorigin" },
                },
            },
        });
    }
}

fn cleanGeneratedAssetsDir(io: std.Io, dest_dir: []const u8) !void {
    std.Io.Dir.cwd().deleteTree(io, dest_dir) catch {};
}
