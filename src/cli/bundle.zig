pub fn register(writer: *std.Io.Writer, reader: *std.Io.Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "bundle",
        .description = "Bundle the site into deployable directory",
    }, bundle);

    try cmd.addFlag(outdir_flag);
    try cmd.addFlag(flag.binpath_flag);
    try cmd.addFlag(flag.install_prefix_flag);

    return cmd;
}

const outdir_flag = zli.Flag{
    .name = "outdir",
    .shortcut = "o",
    .description = "Output directory",
    .type = .String,
    .default_value = .{ .String = "bundle" },
};

fn bundle(ctx: zli.CommandContext) !void {
    const app = AppContext.from(&ctx);
    const io = app.io;
    const outdir = ctx.flag("outdir", []const u8);
    const binpath = ctx.flag("binpath", []const u8);
    const install_prefix = ctx.flag("install-prefix", []const u8);

    // TODO: upon upgrading to Zig 0.17 use the zig build --listen to get build configuration to find binary path
    var app_meta = util.findprogram(io, ctx.allocator, binpath, install_prefix) catch |err| {
        if (err == error.FileNotFound or err == error.ProgramNotFound or err == error.EmptyBinDir) {
            try ctx.writer.print("Run \x1b[34mzig build\x1b[0m to build the ZX executable first!\n", .{});
            return;
        }
        try ctx.writer.print("Error finding ZX executable! {any}\n", .{err});
        return;
    };
    defer util.freeBuildMeta(ctx.allocator, &app_meta);

    const appoutdir = app_meta.rootdir orelse "";
    const final_binpath = app_meta.binpath.?;

    var printer = tui.Printer.init(ctx.allocator, .{ .file_path_mode = .flat, .file_tree_max_depth = 1 });
    defer printer.deinit();

    printer.header("{s} Bundling ZX site!", .{tui.Printer.emoji("○")});
    printer.info("{s}", .{outdir});

    log.debug("Bundling ZX site! binpath={s} rootdir={s}", .{ final_binpath, appoutdir });
    log.debug("Outdir: {s}", .{outdir});

    const bin_name = std.fs.path.basename(final_binpath);
    const dest_binpath = try std.fs.path.join(ctx.allocator, &.{ outdir, bin_name });
    defer ctx.allocator.free(dest_binpath);
    log.debug("Copying bin from {s} to outdir {s}", .{ final_binpath, dest_binpath });

    std.Io.Dir.cwd().createDirPath(io, outdir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    try std.Io.Dir.copyFile(std.Io.Dir.cwd(), final_binpath, std.Io.Dir.cwd(), dest_binpath, io, .{});
    printer.filepath(bin_name);

    const static_outdir = try std.fs.path.join(ctx.allocator, &.{ outdir, "static" });
    defer ctx.allocator.free(static_outdir);
    log.debug("Copying static directory! {s}", .{appoutdir});
    util.copydirs(io, ctx.allocator, appoutdir, &.{"."}, static_outdir, false, &printer) catch |err| {
        std.log.err("Failed to copy static directories: {any}", .{err});
        return err;
    };

    printer.footer("Now run {s}\n\n{s}(cd {s} && ./{s}{s}", .{ tui.Printer.emoji("→"), tui.Colors.cyan, outdir, bin_name, tui.Colors.reset });
}

const std = @import("std");
const zli = @import("zli");
const util = @import("shared/util.zig");
const flag = @import("shared/flag.zig");
const AppContext = @import("shared/context.zig").AppContext;
const tui = @import("../tui/main.zig");
const log = std.log.scoped(.cli);
