const org = "ziex-dev";

pub fn fetch(
    io: std.Io,
    allocator: std.mem.Allocator,
    template: []const u8,
    dest_dir: []const u8,
) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const repo = try std.fmt.allocPrint(allocator, "template-{s}", .{template});
    defer allocator.free(repo);

    const tag = try fetchLatestReleaseTag(&client, allocator, repo);
    defer allocator.free(tag);

    // codeload serves the gzipped source tarball for a given ref.
    const tarball_url = try std.fmt.allocPrint(
        allocator,
        "https://codeload.github.com/{s}/{s}/tar.gz/refs/tags/{s}",
        .{ org, repo, tag },
    );
    defer allocator.free(tarball_url);

    const gz = try get(&client, allocator, tarball_url);
    defer allocator.free(gz);

    try std.Io.Dir.cwd().createDirPath(io, dest_dir);
    var dir = try std.Io.Dir.cwd().openDir(io, dest_dir, .{});
    defer dir.close(io);

    var gz_reader: std.Io.Reader = .fixed(gz);
    var decompress_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress: std.compress.flate.Decompress = .init(&gz_reader, .gzip, &decompress_buf);

    try std.tar.extract(io, dir, &decompress.reader, .{
        .strip_components = 1,
        .mode_mode = .executable_bit_only,
    });

    try customize(io, allocator, dest_dir);
}

/// Query the GitHub API for the latest release tag of `repo`.
fn fetchLatestReleaseTag(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    repo: []const u8,
) ![]const u8 {
    const url = try std.fmt.allocPrint(
        allocator,
        "https://api.github.com/repos/{s}/{s}/releases/latest",
        .{ org, repo },
    );
    defer allocator.free(url);

    const body = try get(client, allocator, url);
    defer allocator.free(body);

    const parsed = std.json.parseFromSlice(struct {
        tag_name: []const u8,
    }, allocator, body, .{ .ignore_unknown_fields = true }) catch return error.NoReleaseFound;
    defer parsed.deinit();

    return allocator.dupe(u8, parsed.value.tag_name);
}

fn get(client: *std.http.Client, allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .redirect_behavior = @enumFromInt(5),
        .response_writer = &aw.writer,
        .extra_headers = &.{
            .{ .name = "user-agent", .value = "ziex-cli" },
            .{ .name = "accept", .value = "application/vnd.github+json" },
        },
    }) catch return error.NetworkError;

    switch (result.status) {
        .ok => {},
        .not_found => return error.TemplateNotFound,
        else => return error.NetworkError,
    }

    return allocator.dupe(u8, aw.written());
}

fn customize(io: std.Io, allocator: std.mem.Allocator, dest_dir: []const u8) !void {
    const project_name = try sanitizeProjectName(allocator, std.fs.path.basename(dest_dir));
    defer allocator.free(project_name);

    var dir = try std.Io.Dir.cwd().openDir(io, dest_dir, .{ .iterate = true });
    defer dir.close(io);

    try replaceInTree(io, allocator, dir, "ziex_app", project_name);
    try updateFingerprint(io, allocator, dest_dir, project_name);
}

fn replaceInTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    from: []const u8,
    to: []const u8,
) !void {
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;

        const data = entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(8 * 1024 * 1024)) catch continue;
        defer allocator.free(data);

        if (std.mem.indexOf(u8, data, from) == null) continue;

        const replaced = try std.mem.replaceOwned(u8, allocator, data, from, to);
        defer allocator.free(replaced);

        try entry.dir.writeFile(io, .{ .sub_path = entry.basename, .data = replaced });
    }
}

fn updateFingerprint(
    io: std.Io,
    allocator: std.mem.Allocator,
    dest_dir: []const u8,
    project_name: []const u8,
) !void {
    const zon_path = try std.fs.path.join(allocator, &.{ dest_dir, "build.zig.zon" });
    defer allocator.free(zon_path);

    const data = std.Io.Dir.cwd().readFileAlloc(io, zon_path, allocator, .limited(1024 * 1024)) catch return;
    defer allocator.free(data);

    const needle = ".fingerprint = 0x";
    const start = std.mem.indexOf(u8, data, needle) orelse return;
    const hex_start = start + needle.len;
    var hex_end = hex_start;
    while (hex_end < data.len and std.ascii.isHex(data[hex_end])) hex_end += 1;

    const fingerprint = Fingerprint.generate(io, project_name);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try out.writer.writeAll(data[0..start]);
    try out.writer.print(".fingerprint = 0x{x:0>16}", .{fingerprint.int()});
    try out.writer.writeAll(data[hex_end..]);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = zon_path, .data = out.written() });
}

const Fingerprint = packed struct(u64) {
    id: u32,
    checksum: u32,

    fn generate(io: std.Io, name: []const u8) Fingerprint {
        var source: std.Random.IoSource = .{ .io = io };
        return .{
            .id = source.interface().intRangeLessThan(u32, 1, 0xffffffff),
            .checksum = std.hash.Crc32.hash(name),
        };
    }

    fn int(n: Fingerprint) u64 {
        return @bitCast(n);
    }
};

fn sanitizeProjectName(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const out = try allocator.alloc(u8, name.len);
    for (name, 0..) |c, i| {
        out[i] = if (std.ascii.isAlphanumeric(c) or c == '_') c else '_';
    }
    return out;
}

const std = @import("std");
