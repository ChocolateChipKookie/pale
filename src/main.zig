const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");
const pale = @import("pale");
const Solution = pale.solution.Solution;
const Canvas = pale.graphics.Canvas;
const Color = pale.graphics.Color;
const CombinedMutation = pale.mutation.CombinedMutation;

const RuntimeError = error{
    InvalidFormat,
    InvalidArgument,
    WrongDimension,
};

fn imageToCanvas(alloc: std.mem.Allocator, image: rl.Image) !Canvas {
    if (image.format != rl.PixelFormat.uncompressed_r8g8b8a8) {
        return RuntimeError.InvalidFormat;
    }
    if (image.width <= 0 or image.height <= 0) {
        return RuntimeError.InvalidArgument;
    }

    const result = try Canvas.init(alloc, @intCast(image.width), @intCast(image.height));
    const image_data: [*]Color = @ptrCast(@alignCast(image.data));
    @memcpy(result.data, image_data);
    return result;
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Set up images and canvases
    var target_image = try rl.Image.init("earring.png");
    defer target_image.unload();
    if (target_image.format != rl.PixelFormat.uncompressed_r8g8b8a8) {
        rl.imageFormat(&target_image, rl.PixelFormat.uncompressed_r8g8b8a8);
    }
    std.log.info("Image size: {d}x{d}", .{ target_image.width, target_image.height });

    const target_canvas = try imageToCanvas(alloc, target_image);
    defer target_canvas.deinit(alloc);

    var best_canvas = try target_canvas.clone(alloc);
    defer best_canvas.deinit(alloc);

    var test_canvas = try target_canvas.clone(alloc);
    defer test_canvas.deinit(alloc);

    // Set up raylib
    rl.setTraceLogLevel(.err);
    rl.initWindow(target_image.width, target_image.height, "Pale");
    defer rl.closeWindow();

    const texture = try rl.Texture2D.fromImage(target_image);
    defer texture.unload();

    // Set up the hill climbing algorithm
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rng = prng.random();

    var best_solution = Solution.init(alloc, 1000, target_canvas.width, target_canvas.height) catch |err| {
        std.log.err("Error allocating solution ({}), exiting!", .{err});
        return;
    };
    defer best_solution.deinit(alloc);
    _ = try best_solution.eval(&target_canvas, &test_canvas);

    var test_solution = try best_solution.clone(alloc);
    defer test_solution.deinit(alloc);

    const mutation = CombinedMutation.init(&rng, target_image.width, target_image.height);

    var buffer: [64]u8 = undefined;
    var counter: i32 = 0;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const start = std.time.microTimestamp();
    const total_time = 60 * std.time.us_per_s;

    const target_fps = 30;
    const target_frame_duration_micro = std.time.us_per_s / target_fps;

    while (!rl.windowShouldClose()) {
        const frame_start = std.time.microTimestamp();
        if (frame_start - start > total_time) {
            break;
        }

        // Update
        while (frame_start + target_frame_duration_micro > std.time.microTimestamp()) {
            counter += 1;
            best_solution.cloneIntoAssumingCapacity(&test_solution);
            mutation.mutate(&test_solution);

            _ = try test_solution.evalRegion(&target_canvas, best_solution, &best_canvas, &test_canvas);
            if (test_solution.fitness.evaluated.total() <= best_solution.fitness.evaluated.total()) {
                test_solution.cloneIntoAssumingCapacity(&best_solution);
                test_solution.draw(&best_canvas);
            }
        }

        rl.updateTexture(texture, @ptrCast(best_canvas.data));

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
            const text = try std.fmt.bufPrintZ(&buffer, "Fitness: {}", .{best_solution.fitness.evaluated.pixelError});
            rl.drawText(text, 10, 40, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "FPS:     {}", .{rl.getFPS()});
            rl.drawText(text, 10, 70, 20, .light_gray);
        }

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Rects:   {}", .{best_solution.data.items.len});
            rl.drawText(text, 10, 100, 20, .light_gray);
        }
    }

    // Sanity chekck, to validate that the partial region-based evaluation did
    // not end up being wrong during some accumulation part
    const fitness_accumulated = best_solution.fitness.evaluated.pixelError;
    _ = try best_solution.eval(&target_canvas, &test_canvas);
    const fitness_evaluated = best_solution.fitness.evaluated.pixelError;
    std.log.info("Actual: {}, Partial: {}, Matching: {}", .{ fitness_evaluated, fitness_accumulated, fitness_accumulated == fitness_evaluated });

    const end = std.time.microTimestamp();
    const totalSeconds = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    try stdout.print("Iterations: {}\n", .{counter});
    try stdout.print("Seconds: {}\n", .{totalSeconds});
    try stdout.print("Iters/second: {}\n", .{@as(f64, @floatFromInt(counter)) / totalSeconds});
    try stdout.print("Normalized error: {}\n", .{@as(f64, @floatFromInt(best_solution.fitness.evaluated.pixelError)) / @as(f64, @floatFromInt(Solution.maxError(target_canvas.width, target_canvas.height)))});
    try stdout.flush();
}
