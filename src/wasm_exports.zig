const std = @import("std");
const rl = @import("raylib");
const Solution = @import("solution.zig").Solution;
const CombinedMutation = @import("mutation.zig").CombinedMutation;

/// Global state for the optimization context
const Context = struct {
    target_image: rl.Image,
    best_canvas: rl.Image,
    test_canvas: rl.Image,
    best_solution: Solution,
    test_solution: Solution,
    mutation: CombinedMutation,
    prng: std.Random.DefaultPrng,
    random: std.Random,
    iteration_count: u64,
    target_fps: u32,
};

const allocator = std.heap.c_allocator;
var last_error_buffer: [512]u8 = undefined;
var last_error: ?[]const u8 = null;

fn report_error(
    comptime format: []const u8,
    args: anytype,
) void {
    if (last_error) |err| {
        std.log.warn("Last reported error was not handled: {s}", .{err});
    }

    last_error = std.fmt.bufPrint(&last_error_buffer, format, args) catch blk: {
        std.log.warn("Error too long, truncated", .{});
        break :blk &last_error_buffer;
    };
}

export fn pale_get_error_ptr() ?[*]const u8 {
    if (last_error) |err| {
        return err.ptr;
    }
    std.log.warn("Trying to get error, when no error is set", .{});
    return null;
}

export fn pale_get_error_len() usize {
    if (last_error) |err| {
        return err.len;
    }
    std.log.warn("Trying to get error length, when no error is set", .{});
    return 0;
}

export fn pale_clear_error() void {
    if (last_error) |_| {
        last_error = null;
        return;
    }
    std.log.warn("Trying to clear error, when no error is set", .{});
}

/// Creates a new optimization context.
/// Takes raw RGBA pixel data from JavaScript (data is copied).
/// Returns null on success, or an error message string on failure.
export fn pale_create(
    target_pixels: [*]const u8,
    width: i32,
    height: i32,
    capacity: u32,
    target_fps: u32,
    seed: u64,
) ?*Context {
    if (target_fps == 0 or 60 < target_fps) {
        report_error("Target FPS has to be in range (0, 60] (got {d})", .{target_fps});
        return null;
    }

    var ctx = allocator.create(Context) catch {
        report_error("Failed to allocate context", .{});
        return null;
    };
    ctx.target_fps = target_fps;

    // Copy target image data
    const pixel_count: usize = @intCast(width * height);
    const pixel_data = allocator.alloc(rl.Color, pixel_count) catch {
        allocator.destroy(ctx);
        report_error("Failed to allocate target image data", .{});
        return null;
    };
    @memcpy(pixel_data, @as([*]const rl.Color, @ptrCast(@alignCast(target_pixels)))[0..pixel_count]);

    ctx.target_image = rl.Image{
        .data = pixel_data.ptr,
        .width = width,
        .height = height,
        .mipmaps = 1,
        .format = .uncompressed_r8g8b8a8,
    };

    // Create canvas images
    ctx.best_canvas = rl.genImageColor(width, height, .black);
    ctx.test_canvas = rl.genImageColor(width, height, .black);

    // Initialize PRNG
    ctx.prng = std.Random.DefaultPrng.init(seed);
    ctx.random = ctx.prng.random();

    // Initialize solutions
    ctx.best_solution = Solution.init(allocator, capacity, width, height) catch {
        allocator.free(pixel_data);
        rl.unloadImage(ctx.best_canvas);
        rl.unloadImage(ctx.test_canvas);
        allocator.destroy(ctx);
        report_error("Failed to allocate best solution", .{});
        return null;
    };

    _ = ctx.best_solution.eval(&ctx.target_image, &ctx.best_canvas) catch {
        ctx.best_solution.deinit(allocator);
        allocator.free(pixel_data);
        rl.unloadImage(ctx.best_canvas);
        rl.unloadImage(ctx.test_canvas);
        allocator.destroy(ctx);
        report_error("Failed to evaluate initial solution", .{});
        return null;
    };

    ctx.test_solution = ctx.best_solution.clone(allocator) catch {
        ctx.best_solution.deinit(allocator);
        allocator.free(pixel_data);
        rl.unloadImage(ctx.best_canvas);
        rl.unloadImage(ctx.test_canvas);
        allocator.destroy(ctx);
        report_error("Failed to clone test solution", .{});
        return null;
    };

    ctx.mutation = CombinedMutation.init(&ctx.random, width, height);
    ctx.iteration_count = 0;

    return ctx;
}

/// Destroys the optimization context and frees all resources.
export fn pale_destroy(mb_context: ?*Context) bool {
    const context = mb_context orelse {
        report_error("Passed context is null", .{});
        return false;
    };

    context.best_solution.deinit(allocator);
    context.test_solution.deinit(allocator);

    // Free the copied target image data
    const pixel_count: usize = @intCast(context.target_image.width * context.target_image.height);
    const pixel_data: [*]rl.Color = @ptrCast(@alignCast(context.target_image.data));
    allocator.free(pixel_data[0..pixel_count]);

    rl.unloadImage(context.best_canvas);
    rl.unloadImage(context.test_canvas);

    allocator.destroy(context);
    return true;
}

/// Run optimization step, rougly aiming to get the right number of iterations to satisfy the target FPS
export fn pale_run_step(context: ?*Context) u64 {
    const ctx = context orelse {
        report_error("Passed context is null", .{});
        return 0;
    };

    const start = std.time.microTimestamp();
    const end = start + std.time.us_per_s / ctx.target_fps;
    while (end > std.time.microTimestamp()) {
        ctx.best_solution.cloneIntoAssumingCapacity(&ctx.test_solution);
        ctx.mutation.mutate(&ctx.test_solution);
        _ = ctx.test_solution.evalRegion(&ctx.target_image, ctx.best_solution, &ctx.best_canvas, &ctx.test_canvas) catch {
            report_error("Error evaluating region", .{});
            return 0;
        };
        if (ctx.test_solution.fitness.evaluated.total() < ctx.best_solution.fitness.evaluated.total()) {
            ctx.test_solution.cloneIntoAssumingCapacity(&ctx.best_solution);
            ctx.test_solution.draw(&ctx.best_canvas);
        }
        ctx.iteration_count += 1;
    }

    return ctx.best_solution.fitness.evaluated.pixelError;
}

/// Get image
export fn pale_get_best_image(context: ?*Context) ?[*]const u8 {
    const ctx = context orelse {
        report_error("Passed context is null", .{});
        return null;
    };

    return @ptrCast(ctx.best_canvas.data);
}

/// Get total iterations
export fn pale_get_iterations(context: ?*Context) u64 {
    const ctx = context orelse {
        report_error("Passed context is null", .{});
        return 0;
    };

    if (ctx.iteration_count == 0) {
        report_error("The program has not been run yet", .{});
        return 0;
    }

    return ctx.iteration_count;
}
