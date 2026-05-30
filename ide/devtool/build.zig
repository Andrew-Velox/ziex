const std = @import("std");
const ziex = @import("ziex");
const esbuild = @import("esbuild");

const Platform = enum {
    chromium,
    firefox,
    development,
};

pub fn build(b: *std.Build) !void {
    // --- Target and Optimize from `zig build` arguments ---
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    const platform = b.option(Platform, "platform", "Platform to build for") orelse .development;
    build_options.addOption(Platform, "platform", platform);

    const exe = b.addExecutable(.{
        .name = "ziex_devtool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    exe.root_module.addOptions("build_options", build_options);
    var ziex_b = try ziex.init(b, exe, .{
        .client = .{
            .jsglue_href = switch (platform) {
                .chromium => "/pages/assets/_/main.js",
                else => "/assets/_/main.js",
            },
            .wasm_href = switch (platform) {
                .chromium => "/pages/assets/_/main.wasm",
                else => "/assets/_/main.wasm",
            },
        },
    });
    ziex_b = ziex_b;

    const is_release = optimize != .Debug;
    const client_scripts = esbuild.addBuild(b, .{
        .name = "devtool_scripts",
        .config = .{
            .entrypoints = &.{
                b.path("app/scripts/client.ts"),
            },
            .platform = .browser,
            .minify = is_release,
            .sourcemap = if (is_release) .none else .@"inline",
            .define = &.{
                .{ .key = "__DEV__", .value = if (is_release) "false" else "true" },
                .{ .key = "process.env.NODE_ENV", .value = if (is_release) "\"production\"" else "\"development\"" },
            },
        },
    });

    const install_main_js = b.addInstallFile(client_scripts.dir.path(b, "client.js"), "static/assets/_/main.js");
    b.default_step.dependOn(&install_main_js.step);

    // Step: zig build chromium
    const chromium_step = b.step("chromium", "Build chromium extension");
    const chromium_build = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "-Dplatform=chromium" });
    const chromium_export = b.addRunArtifact(ziex_b.cli.exe);
    chromium_export.addArgs(&.{ "export", "--outdir" });
    chromium_export.addDirectoryArg(b.path("../chromium/pages"));
    chromium_export.step.dependOn(&chromium_build.step);

    const chromium_zip = b.addSystemCommand(&.{ "zip", "-r" });
    chromium_zip.setCwd(b.path("../chromium"));
    const zip_output = chromium_zip.addOutputFileArg("ziex-devtools-chromium.zip");
    chromium_zip.addArgs(&.{"."});
    chromium_zip.step.dependOn(&chromium_export.step);

    const install_zip = b.addInstallFileWithDir(zip_output, .{ .custom = "../../chromium/dist" }, "ziex-devtools-chromium.zip");
    chromium_step.dependOn(&install_zip.step);
}
