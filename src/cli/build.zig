pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "build",
        .description = "Build the app (equivalent to `zig build`)",
    }, build);

    var build_args_flag = flags.build_args;
    build_args_flag.default_value = .{ .String = "-Doptimize=ReleaseFast" };
    try cmd.addFlag(build_args_flag);

    return cmd;
}

fn build(ctx: zli.CommandContext) !void {
    const app = AppContext.from(&ctx);
    const io = app.io;
    const allocator = ctx.allocator;

    var build_args = std.ArrayList([]const u8).empty;
    defer build_args.deinit(allocator);
    try build_args.appendSlice(allocator, &.{ cli_options.zig_exe, "build" });

    var i_build_args = std.mem.splitSequence(u8, ctx.flag("build-args", []const u8), " ");
    while (i_build_args.next()) |arg| {
        const trimmed_arg = std.mem.trim(u8, arg, " ");
        if (std.mem.eql(u8, trimmed_arg, "")) continue;
        try build_args.append(allocator, trimmed_arg);
    }

    var system = try std.process.spawn(io, .{
        .argv = build_args.items,
        .stderr = .pipe,
        .stdout = .ignore,
    });
    defer system.kill(io);

    try formatBuildErrors(io, allocator, ctx.writer, &system);

    const term = try system.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) std.process.exit(code),
        else => std.process.exit(1),
    }
}

fn formatBuildErrors(
    io: std.Io,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    system: *std.process.Child,
) !void {
    var stderr_file = system.stderr.?;
    var raw_buf: [8192]u8 = undefined;
    var streaming_reader = stderr_file.readerStreaming(io, &raw_buf);
    const io_reader = &streaming_reader.interface;

    var diagnostics = std.ArrayList(Builder.Diagnostic).empty;
    defer {
        for (diagnostics.items) |d| {
            allocator.free(d.file);
            allocator.free(d.message);
            if (d.source_line) |sl| allocator.free(sl);
            if (d.caret_line) |cl| allocator.free(cl);
        }
        diagnostics.deinit(allocator);
    }

    var line_writer = std.Io.Writer.Allocating.init(allocator);
    defer line_writer.deinit();

    while (io_reader.streamDelimiter(&line_writer.writer, '\n')) |_| {
        const line = line_writer.written();
        _ = io_reader.takeByte() catch {};

        if (Builder.parseDiagnostic(allocator, line)) |diag| {
            try diagnostics.append(allocator, diag);
        } else if (diagnostics.items.len > 0) {
            var last_diag = &diagnostics.items[diagnostics.items.len - 1];
            if (last_diag.source_line == null) {
                if (line.len > 0) {
                    last_diag.source_line = try allocator.dupe(u8, line);
                    line_writer.clearRetainingCapacity();
                    continue;
                }
            } else if (last_diag.caret_line == null) {
                if (std.mem.indexOfAny(u8, line, "^~") != null) {
                    last_diag.caret_line = try allocator.dupe(u8, line);
                    line_writer.clearRetainingCapacity();
                    continue;
                }
            }
        }

        line_writer.clearRetainingCapacity();
    } else |err| {
        if (err != error.EndOfStream) return err;
    }

    if (diagnostics.items.len == 0) return;

    Diagnostics.remap(allocator, diagnostics.items);
    const deduped = Diagnostics.dedupe(allocator, diagnostics.items);
    diagnostics.shrinkRetainingCapacity(deduped.len);

    const formatted = try Diagnostics.formatOxlint(allocator, deduped);
    defer allocator.free(formatted);

    try writer.writeAll(formatted);
}

const std = @import("std");
const zli = @import("zli");
const flags = @import("shared/flag.zig");
const AppContext = @import("shared/context.zig").AppContext;
const cli_options = @import("cli_options");
const Builder = @import("dev/Builder.zig");
const Diagnostics = @import("dev/Diagnostics.zig");
const log = std.log.scoped(.cli);
