const std = @import("std");
const pale = @import("pale");
const Solution = pale.solution.Solution;
const CombinedMutation = pale.mutation.CombinedMutation;
const Canvas = pale.graphics.Canvas;
const Color = pale.graphics.Color;

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

/// Global state for the optimization context
const Context = struct {
    target_canvas: Canvas,
    best_canvas: Canvas,
    test_canvas: Canvas,
    best_solution: Solution,
    test_solution: Solution,
    mutation: CombinedMutation,
    prng: std.Random.DefaultPrng,
    random: std.Random,
    iteration_count: u64,
    target_fps: u32,

    fn init(
        alloc: std.mem.Allocator,
        target_pixels: [*]const u8,
        width: i32,
        height: i32,
        capacity: u32,
        target_fps: u32,
        seed: u64,
    ) !*Context {
        // Validate data
        if (target_fps == 0 or 60 < target_fps) {
            report_error("Invalid FPS: {d} (valid range (0, 60]", .{target_fps});
            return error.InvalidArgument;
        }
        // Create canvases
        const target_canvas = Canvas.init(alloc, @intCast(width), @intCast(height)) catch |e| {
            report_error("Failed to initialize target canvas", .{});
            return e;
        };
        const image_data: [*]const Color = @ptrCast(@alignCast(target_pixels));
        @memcpy(target_canvas.data, image_data);

        var best_canvas = target_canvas.clone(alloc) catch |e| {
            target_canvas.deinit(alloc);
            report_error("Failed to initialize best canvas", .{});
            return e;
        };
        best_canvas.clear(.black);

        const test_canvas = target_canvas.clone(alloc) catch |e| {
            target_canvas.deinit(alloc);
            best_canvas.deinit(alloc);
            report_error("Failed to initialize test canvas", .{});
            return e;
        };
        test_canvas.clear(.black);

        // PRNG
        var prng = std.Random.DefaultPrng.init(seed);
        const random = prng.random();

        // Solutions
        var best_solution = Solution.init(alloc, capacity, @intCast(width), @intCast(height)) catch |e| {
            target_canvas.deinit(alloc);
            best_canvas.deinit(alloc);
            test_canvas.deinit(alloc);
            report_error("Failed to initialize best solution", .{});
            return e;
        };

        _ = best_solution.eval(&target_canvas, &best_canvas) catch |e| {
            target_canvas.deinit(alloc);
            best_canvas.deinit(alloc);
            test_canvas.deinit(alloc);
            best_solution.deinit(alloc);
            report_error("Failed to do initial evaluation", .{});
            return e;
        };

        const test_solution = best_solution.clone(alloc) catch |e| {
            target_canvas.deinit(alloc);
            best_canvas.deinit(alloc);
            test_canvas.deinit(alloc);
            best_solution.deinit(alloc);
            report_error("Failed to initialize test solution", .{});
            return e;
        };

        // Mutations
        const mutation = CombinedMutation.init(&random, width, height);

        // Final assembly
        const ctx = alloc.create(Context) catch |e| {
            target_canvas.deinit(alloc);
            best_canvas.deinit(alloc);
            test_canvas.deinit(alloc);
            best_solution.deinit(alloc);
            report_error("Failed to allocate context", .{});
            return e;
        };
        ctx.* = Context{
            .target_canvas = target_canvas,
            .best_canvas = best_canvas,
            .test_canvas = test_canvas,
            .best_solution = best_solution,
            .test_solution = test_solution,
            .mutation = mutation,
            .prng = prng,
            .random = random,
            .iteration_count = 0,
            .target_fps = target_fps,
        };
        return ctx;
    }

    fn deinit(self: *Context, alloc: std.mem.Allocator) void {
        self.target_canvas.deinit(alloc);
        self.best_canvas.deinit(alloc);
        self.test_canvas.deinit(alloc);
        self.best_solution.deinit(alloc);
    }
};

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
    return Context.init(
        allocator,
        target_pixels,
        width,
        height,
        capacity,
        target_fps,
        seed,
    ) catch null;
}

/// Destroys the optimization context and frees all resources.
export fn pale_destroy(mb_context: ?*Context) bool {
    const context = mb_context orelse {
        report_error("Passed context is null", .{});
        return false;
    };

    context.deinit(allocator);
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
        _ = ctx.test_solution.evalRegion(&ctx.target_canvas, ctx.best_solution, &ctx.best_canvas, &ctx.test_canvas) catch {
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
