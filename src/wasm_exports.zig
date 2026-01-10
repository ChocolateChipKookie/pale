const std = @import("std");
const pale = @import("pale");
const Solution = pale.solution.Solution;
const CombinedMutation = pale.mutation.CombinedMutation;
const Canvas = pale.graphics.Canvas;
const Color = pale.graphics.Color;

// Logs disabled to be able to compile with : wasm-freestanding
pub const std_options: std.Options = .{
    .logFn = struct {
        pub fn log(
            comptime _: std.log.Level,
            comptime _: @TypeOf(.enum_literal),
            comptime _: []const u8,
            _: anytype,
        ) void {}
    }.log,
};

const allocator = std.heap.wasm_allocator;
var last_error_buffer: [512]u8 = undefined;
var last_error: ?[]const u8 = null;

fn report_error(
    comptime format: []const u8,
    args: anytype,
) void {
    last_error = std.fmt.bufPrint(&last_error_buffer, format, args) catch &last_error_buffer;
}

export fn pale_get_error_ptr() ?[*]const u8 {
    if (last_error) |err| {
        return err.ptr;
    }
    return null;
}

export fn pale_get_error_len() usize {
    if (last_error) |err| {
        return err.len;
    }
    return 0;
}

export fn pale_clear_error() void {
    last_error = null;
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

        const ctx = alloc.create(Context) catch |e| {
            report_error("Failed to allocate context", .{});
            return e;
        };

        // Create canvases
        ctx.target_canvas = Canvas.init(alloc, @intCast(width), @intCast(height)) catch |e| {
            alloc.destroy(ctx);
            report_error("Failed to initialize target canvas", .{});
            return e;
        };

        ctx.best_canvas = ctx.target_canvas.clone(alloc) catch |e| {
            ctx.target_canvas.deinit(alloc);
            alloc.destroy(ctx);
            report_error("Failed to initialize best canvas", .{});
            return e;
        };
        ctx.best_canvas.clear(.black);

        ctx.test_canvas = ctx.target_canvas.clone(alloc) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            alloc.destroy(ctx);
            report_error("Failed to initialize test canvas", .{});
            return e;
        };
        ctx.test_canvas.clear(.black);

        // Solutions
        ctx.best_solution = Solution.init(alloc, capacity, @intCast(width), @intCast(height)) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            ctx.test_canvas.deinit(alloc);
            alloc.destroy(ctx);
            report_error("Failed to initialize best solution", .{});
            return e;
        };

        _ = ctx.best_solution.eval(&ctx.target_canvas, &ctx.best_canvas) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            ctx.test_canvas.deinit(alloc);
            ctx.best_solution.deinit(alloc);
            alloc.destroy(ctx);
            report_error("Failed to do initial evaluation", .{});
            return e;
        };

        ctx.test_solution = ctx.best_solution.clone(alloc) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            ctx.test_canvas.deinit(alloc);
            ctx.best_solution.deinit(alloc);
            alloc.destroy(ctx);
            report_error("Failed to initialize test solution", .{});
            return e;
        };

        // PRNG
        ctx.prng = std.Random.DefaultPrng.init(seed);
        ctx.random = ctx.prng.random();

        // Mutations
        ctx.mutation = CombinedMutation.init(&ctx.random, width, height);
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
    width: i32,
    height: i32,
    capacity: u32,
    target_fps: u32,
    seed: u64,
) ?*Context {
    return Context.init(
        allocator,
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

    if (ctx.best_solution.fitness == .evaluated and ctx.best_solution.fitness.evaluated.pixelError == 0) {
        report_error("Best solution not evaluated", .{});
        return 0;
    }

    for (0..1000) |_| {
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

/// Get target location
export fn pale_get_target_image(context: ?*Context) ?[*]const u8 {
    const ctx = context orelse {
        report_error("Passed context is null", .{});
        return null;
    };

    return @ptrCast(ctx.target_canvas.data);
}

/// Evaluate best solution
export fn pale_evaluate_best_solution(context: ?*Context) u64 {
    const ctx = context orelse {
        report_error("Passed context is null", .{});
        return 0;
    };

    _ = ctx.best_solution.eval(&ctx.target_canvas, &ctx.best_canvas) catch {
        report_error("Error evaluating solution", .{});
        return 0;
    };

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
