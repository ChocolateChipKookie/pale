const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("pale", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_step = b.step("run", "Run the app");

    if (target.query.os_tag == .freestanding) {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/wasm_exports.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pale", .module = mod },
            },
        });
        const wasm = b.addExecutable(.{
            .name = "pale",
            .root_module = exe_mod,
        });
        wasm.rdynamic = true;
        wasm.entry = .disabled;

        const install_wasm = b.addInstallArtifact(wasm, .{
            .dest_dir = .{ .override = .{ .custom = "web" } },
        });

        const web_files = [_][]const u8{ "index.html", "style.css", "main.js", "pale-worker.js" };
        for (web_files) |file| {
            const install = b.addInstallFile(b.path(b.fmt("web/{s}", .{file})), file);
            install.dir = .{ .custom = "web" };
            b.getInstallStep().dependOn(&install.step);
        }

        var wasm_step = b.step("wasm", "Build WASM for browser");
        wasm_step.dependOn(&install_wasm.step);
        b.getInstallStep().dependOn(wasm_step);
    } else {
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
