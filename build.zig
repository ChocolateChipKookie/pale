const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Native build
    const mod = b.addModule("pale", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pale", .module = mod },
        },
    });
    exe_mod.addImport("raylib", raylib);
    exe_mod.addImport("raygui", raygui);

    exe_mod.linkLibrary(raylib_artifact);

    const exe = b.addExecutable(.{
        .name = "pale",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // WASM build
    const wasm_target = b.resolveTargetQuery(
        .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{.relaxed_simd}),
        },
    );

    const wasm_mod = b.addModule("pale-wasm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = optimize,
    });

    const wasm_root = b.createModule(.{
        .root_source_file = b.path("src/wasm_exports.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pale", .module = wasm_mod },
        },
    });

    const wasm = b.addExecutable(.{
        .name = "pale",
        .root_module = wasm_root,
    });
    wasm.rdynamic = true;
    wasm.entry = .disabled;

    // Inline the web sources into one index.html, brotli it, enforce the
    // budget: 10 * MSS = the "fits in 10 TCP packets" single-round-trip target.
    const mss = 1460;
    const size_budget = 10 * mss;

    const bundle = b.addSystemCommand(&.{"python3"});
    bundle.addFileArg(b.path("web/bundle.py"));
    bundle.addFileArg(b.path("web/index.html"));
    bundle.addFileArg(b.path("web/style.css"));
    bundle.addFileArg(b.path("web/main.js"));
    bundle.addFileArg(b.path("web/pale-worker.js"));
    bundle.addFileArg(wasm.getEmittedBin());
    bundle.addFileArg(b.path("web/favicon.png"));
    const bundled_html = bundle.addOutputFileArg("index.html");
    const bundled_br = bundle.addOutputFileArg("index.html.br");
    bundle.addArg(b.fmt("{d}", .{size_budget}));
    if (optimize == .ReleaseSmall) bundle.addArg("--enforce");

    const wasm_step = b.step("wasm", "Build the self-contained web app");
    wasm_step.dependOn(&b.addInstallFileWithDir(bundled_html, .{ .custom = "web" }, "index.html").step);
    wasm_step.dependOn(&b.addInstallFileWithDir(bundled_br, .{ .custom = "web" }, "index.html.br").step);

    const size_step = b.step("size", "Check the brotli size budget for index.html.br");
    size_step.dependOn(&bundle.step);

    // Resize resources/images/* into the web output dir at build time. Optional
    // so the wasm size-budget CI job can skip raylib's desktop (GL/X11) deps.
    const gen_thumbnails = b.option(bool, "thumbnails", "Generate example thumbnails (needs raylib desktop deps)") orelse true;
    if (gen_thumbnails) {
        const thumbnail_dep = b.dependency("raylib_zig", .{
            .target = target,
            .optimize = .ReleaseSafe,
        });
        const thumbnail_mod = b.createModule(.{
            .root_source_file = b.path("src/thumbnail.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        });
        thumbnail_mod.addImport("raylib", thumbnail_dep.module("raylib"));
        thumbnail_mod.linkLibrary(thumbnail_dep.artifact("raylib"));

        const thumbnail_exe = b.addExecutable(.{
            .name = "thumbnail",
            .root_module = thumbnail_mod,
        });
        // LTO chokes on the system .so paths in raylib's archive.
        thumbnail_exe.lto = .none;

        const run_thumbnails = b.addRunArtifact(thumbnail_exe);
        const thumbnails_out = run_thumbnails.addOutputDirectoryArg("thumbnails");
        run_thumbnails.addArgs(&.{ "256", "720" });

        // Enumerate sources, sorted for a stable cache key and grid order.
        const images_dir = "resources/images";
        const io = b.graph.io;
        var image_names: std.ArrayList([]const u8) = .empty;
        if (b.build_root.handle.openDir(io, images_dir, .{ .iterate = true })) |images_const| {
            var images = images_const;
            defer images.close(io);
            var it = images.iterate();
            while (it.next(io) catch @panic("failed to read " ++ images_dir)) |entry| {
                if (entry.kind != .file) continue;
                if (!std.ascii.endsWithIgnoreCase(entry.name, ".png")) continue;
                image_names.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
            }
        } else |_| {}
        std.mem.sort([]const u8, image_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, c: []const u8) bool {
                return std.mem.lessThan(u8, a, c);
            }
        }.lessThan);

        // File args (not addDirectoryArg) so the cache key tracks image contents.
        // images.json lists the base names for the web thumbnail picker.
        var manifest: std.ArrayList(u8) = .empty;
        manifest.append(b.allocator, '[') catch @panic("OOM");
        for (image_names.items, 0..) |name, i| {
            run_thumbnails.addFileArg(b.path(b.fmt("{s}/{s}", .{ images_dir, name })));
            const stem = name[0 .. name.len - ".png".len];
            if (i != 0) manifest.append(b.allocator, ',') catch @panic("OOM");
            manifest.appendSlice(b.allocator, b.fmt("\"{s}\"", .{stem})) catch @panic("OOM");
        }
        manifest.append(b.allocator, ']') catch @panic("OOM");

        const wf = b.addWriteFiles();
        const manifest_lp = wf.add("images.json", manifest.items);
        const install_manifest = b.addInstallFileWithDir(manifest_lp, .{ .custom = "web" }, "images.json");

        const install_thumbnails = b.addInstallDirectory(.{
            .source_dir = thumbnails_out,
            .install_dir = .{ .custom = "web" },
            .install_subdir = "",
        });
        wasm_step.dependOn(&install_thumbnails.step);
        wasm_step.dependOn(&install_manifest.step);
    }

    // Tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    const wasm_exports_test_mod = b.createModule(.{
        .root_source_file = b.path("src/wasm_exports_test.zig"),
        .target = target,
        .optimize = .Debug,
        .single_threaded = true,
        .imports = &.{
            .{ .name = "pale", .module = mod },
        },
    });

    const wasm_exports_test = b.addTest(.{
        .root_module = wasm_exports_test_mod,
    });

    const wasm_exports_test_step = b.step("wasm-exports-test", "Native Debug smoke-test of wasm exports");
    wasm_exports_test_step.dependOn(&b.addRunArtifact(wasm_exports_test).step);
}
