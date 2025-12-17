const std = @import("std");
const rlz = @import("raylib_zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const mod = b.addModule("pale", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

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

    const run_step = b.step("run", "Run the app");

    if (target.query.os_tag == .emscripten) {
        const emsdk = rlz.emsdk;

        const wasm_mod = b.createModule(.{
            .root_source_file = b.path("src/wasm_exports.zig"),
            .target = target,
            .optimize = optimize,
        });
        wasm_mod.addImport("raylib", raylib);

        const wasm = b.addLibrary(.{
            .name = "pale",
            .root_module = wasm_mod,
        });

        const install_dir: std.Build.InstallDir = .{ .custom = "web" };
        const emcc_flags = emsdk.emccDefaultFlags(b.allocator, .{ .optimize = optimize });
        var emcc_settings = emsdk.emccDefaultSettings(b.allocator, .{ .optimize = optimize });

        // Export our WASM functions
        const exported_funcs = [_][]const u8{
            "_pale_create",
            "_pale_destroy",
            "_pale_get_error_ptr",
            "_pale_get_error_len",
            "_pale_clear_error",
            "_malloc",
            "_free",
        };

        const exports_json = try std.fmt.allocPrint(b.allocator, "{f}", .{std.json.fmt(exported_funcs, .{})});
        emcc_settings.put("EXPORTED_FUNCTIONS", exports_json) catch unreachable;
        emcc_settings.put("EXPORTED_RUNTIME_METHODS", "['ccall','cwrap']") catch unreachable;

        const emcc_step = emsdk.emccStep(b, raylib_artifact, wasm, .{
            .optimize = optimize,
            .flags = emcc_flags,
            .settings = emcc_settings,
            .install_dir = install_dir,
        });

        // Remove the auto-generated html file
        const html_filename = try std.fmt.allocPrint(b.allocator, "{s}.html", .{wasm.name});
        const remove_html_file = b.addRemoveDirTree(.{ .cwd_relative = b.getInstallPath(install_dir, html_filename) });
        remove_html_file.step.dependOn(emcc_step);

        // Move all of our html assets to the right location
        const install_web_artifacts = b.addInstallFile(b.path("web/index.html"), "index.html");
        install_web_artifacts.dir = install_dir;
        install_web_artifacts.step.dependOn(&remove_html_file.step);
        b.getInstallStep().dependOn(&install_web_artifacts.step);

        const emrun_step = emsdk.emrunStep(
            b,
            b.getInstallPath(install_dir, html_filename),
            &.{},
        );

        emrun_step.dependOn(emcc_step);
        run_step.dependOn(emrun_step);
    } else {
        const exe = b.addExecutable(.{
            .name = "pale",
            .root_module = exe_mod,
        });
        exe.linkLibrary(raylib_artifact);

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const mod_tests = b.addTest(.{
            .root_module = mod,
        });

        const run_mod_tests = b.addRunArtifact(mod_tests);

        const exe_tests = b.addTest(.{
            .root_module = exe.root_module,
        });

        const run_exe_tests = b.addRunArtifact(exe_tests);

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
    }
}
