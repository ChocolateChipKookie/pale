const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const Solution = @import("solution.zig").Solution;
const CombinedMutation = @import("mutation.zig").CombinedMutation;

/// Wrapper to handle allocator differences between native and WASM builds
const AllocatorWrapper = if (builtin.target.os.tag == .emscripten)
    struct {
        fn init() @This() {
            return .{};
        }
        fn deinit(_: *@This()) void {}
        fn allocator(_: *@This()) std.mem.Allocator {
            return std.heap.c_allocator;
        }
    }
else
    struct {
        gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},

        fn init() @This() {
            return .{};
        }
        fn deinit(self: *@This()) void {
            _ = self.gpa.deinit();
        }
        fn allocator(self: *@This()) std.mem.Allocator {
            return self.gpa.allocator();
        }
    };

pub fn main() anyerror!void {
    var alloc_wrapper = AllocatorWrapper.init();
    defer alloc_wrapper.deinit();
    const alloc = alloc_wrapper.allocator();

    var targetImage = try rl.Image.init("earring.png");
    defer targetImage.unload();
    if (targetImage.format != rl.PixelFormat.uncompressed_r8g8b8a8) {
        rl.imageFormat(&targetImage, rl.PixelFormat.uncompressed_r8g8b8a8);
    }

    std.log.info("Image size: {d}x{d}", .{ targetImage.width, targetImage.height });

    var bestCanvasImage = targetImage.copy();
    defer bestCanvasImage.unload();

    var canvasImage = targetImage.copy();
    defer canvasImage.unload();

    rl.setTraceLogLevel(.err);
    rl.initWindow(targetImage.width, targetImage.height, "Pale");
    defer rl.closeWindow();

    const texture = try rl.Texture2D.fromImage(canvasImage);
    defer texture.unload();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rng = prng.random();

    var bestSolution = Solution.init(alloc, 1000, targetImage.width, targetImage.height) catch |err| {
        std.log.err("Error allocating solution ({}), exiting!", .{err});
        return;
    };
    defer bestSolution.deinit(alloc);
    _ = try bestSolution.eval(&targetImage, &canvasImage);
    var testSolution = try bestSolution.clone(alloc);
    defer testSolution.deinit(alloc);

    const mutation = CombinedMutation.init(&rng, targetImage.width, targetImage.height);

    var buffer: [64]u8 = undefined;
    var counter: i32 = 0;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const start = std.time.microTimestamp();
    const totalTime = std.time.us_per_min;

    const targetFps = 30;
    const targetFrameDurationMicro = std.time.us_per_s / targetFps;

    while (!rl.windowShouldClose()) {
        const frameStart = std.time.microTimestamp();
        if (frameStart - start > totalTime) {
            break;
        }

        // Update
        while (frameStart + targetFrameDurationMicro > std.time.microTimestamp()) {
            counter += 1;
            bestSolution.cloneIntoAssumingCapacity(&testSolution);
            mutation.mutate(&testSolution);

            _ = try testSolution.evalRegion(&targetImage, bestSolution, &bestCanvasImage, &canvasImage);
            if (testSolution.fitness.evaluated.total() <= bestSolution.fitness.evaluated.total()) {
                testSolution.cloneIntoAssumingCapacity(&bestSolution);
                testSolution.draw(&bestCanvasImage);
            }
        }

        rl.updateTexture(texture, bestCanvasImage.data);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);
        rl.drawTexture(texture, 0, 0, .white);

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Counter: {}", .{counter});
            rl.drawText(text, 10, 10, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "Fitness: {}", .{bestSolution.fitness.evaluated.pixelError});
            rl.drawText(text, 10, 40, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "FPS:     {}", .{rl.getFPS()});
            rl.drawText(text, 10, 70, 20, .light_gray);
        }

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Rects:   {}", .{bestSolution.data.items.len});
            rl.drawText(text, 10, 100, 20, .light_gray);
        }
    }

    const end = std.time.microTimestamp();
    const totalSeconds = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    try stdout.print("Iterations: {}\n", .{counter});
    try stdout.print("Seconds: {}\n", .{totalSeconds});
    try stdout.print("Iters/second: {}\n", .{@as(f64, @floatFromInt(counter)) / totalSeconds});
    try stdout.print("Normalized error: {}\n", .{@as(f64, @floatFromInt(bestSolution.fitness.evaluated.pixelError)) / @as(f64, @floatFromInt(Solution.maxError(targetImage.width, targetImage.height)))});
    try stdout.flush();

    _ = bestCanvasImage.exportToFile("out.png");
}
