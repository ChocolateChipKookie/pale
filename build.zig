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
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

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

    const install_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "web" } },
    });

    const web_files = [_][]const u8{ "index.html", "style.css", "main.js", "pale-worker.js" };
    for (web_files) |file| {
        const install = b.addInstallFileWithDir(
            b.path(b.fmt("web/{s}", .{file})),
            .{ .custom = "web" },
            file,
        );
        install_wasm.step.dependOn(&install.step);
    }

    const wasm_step = b.step("wasm", "Build WASM for browser");
    wasm_step.dependOn(&install_wasm.step);

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
