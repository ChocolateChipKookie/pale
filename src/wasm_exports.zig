const std = @import("std");
const pale = @import("pale");
const Solution = pale.solution.Solution;
const CombinedMutation = pale.mutation.CombinedMutation;
const Canvas = pale.graphics.Canvas;
const Color = pale.graphics.Color;

extern "env" fn jsLog(message_level: u8, ptr: [*]const u8, len: usize) void;

// log overwritten to be able to compile with wasm-freestanding
pub const std_options: std.Options = .{
    .logFn = struct {
        pub fn log(
            comptime message_level: std.log.Level,
            comptime _: @TypeOf(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            var error_buffer: [512]u8 = undefined;
            const written = std.fmt.bufPrint(&error_buffer, format, args) catch
                std.fmt.bufPrint(&error_buffer, "Error writing to error buffer", .{}) catch "";
            jsLog(@intFromEnum(message_level), written.ptr, written.len);
        }
    }.log,
};

const allocator = std.heap.wasm_allocator;

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

    fn init(
        alloc: std.mem.Allocator,
        width: i32,
        height: i32,
        capacity: u32,
        seed: u64,
    ) !*Context {
        const ctx = alloc.create(Context) catch |e| {
            std.log.err("Failed to allocate context", .{});
            return e;
        };

        // Create canvases
        ctx.target_canvas = Canvas.init(alloc, @intCast(width), @intCast(height)) catch |e| {
            alloc.destroy(ctx);
            std.log.err("Failed to initialize target canvas", .{});
            return e;
        };

        ctx.best_canvas = ctx.target_canvas.clone(alloc) catch |e| {
            ctx.target_canvas.deinit(alloc);
            alloc.destroy(ctx);
            std.log.err("Failed to initialize best canvas", .{});
            return e;
        };
        ctx.best_canvas.clear(.black);

        ctx.test_canvas = ctx.target_canvas.clone(alloc) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            alloc.destroy(ctx);
            std.log.err("Failed to initialize test canvas", .{});
            return e;
        };
        ctx.test_canvas.clear(.black);

        // Solutions
        ctx.best_solution = Solution.init(alloc, capacity, @intCast(width), @intCast(height)) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            ctx.test_canvas.deinit(alloc);
            alloc.destroy(ctx);
            std.log.err("Failed to initialize best solution", .{});
            return e;
        };

        _ = ctx.best_solution.eval(&ctx.target_canvas, &ctx.best_canvas) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            ctx.test_canvas.deinit(alloc);
            ctx.best_solution.deinit(alloc);
            alloc.destroy(ctx);
            std.log.err("Failed to do initial evaluation", .{});
            return e;
        };

        ctx.test_solution = ctx.best_solution.clone(alloc) catch |e| {
            ctx.target_canvas.deinit(alloc);
            ctx.best_canvas.deinit(alloc);
            ctx.test_canvas.deinit(alloc);
            ctx.best_solution.deinit(alloc);
            alloc.destroy(ctx);
            std.log.err("Failed to initialize test solution", .{});
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
    seed: u64,
) ?*Context {
    std.log.err("All good my friends", .{});
    return Context.init(
        allocator,
        width,
        height,
        capacity,
        seed,
    ) catch null;
}

/// Destroys the optimization context and frees all resources.
export fn pale_destroy(mb_context: ?*Context) bool {
    const context = mb_context orelse {
        std.log.err("Passed context is null", .{});
        return false;
    };

    context.deinit(allocator);
    allocator.destroy(context);
    return true;
}

/// Run optimization steps
export fn pale_run_steps(context: ?*Context, iterations: usize) u64 {
    const ctx = context orelse {
        std.log.err("Passed context is null", .{});
        return 0;
    };

    if (ctx.best_solution.fitness == .evaluated and ctx.best_solution.fitness.evaluated.pixelError == 0) {
        std.log.err("Best solution not evaluated", .{});
        return 0;
    }

    for (0..iterations) |_| {
        ctx.best_solution.cloneIntoAssumingCapacity(&ctx.test_solution);
        ctx.mutation.mutate(&ctx.test_solution);
        _ = ctx.test_solution.evalRegion(&ctx.target_canvas, ctx.best_solution, &ctx.best_canvas, &ctx.test_canvas) catch {
            std.log.err("Error evaluating region", .{});
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
        std.log.err("Passed context is null", .{});
        return null;
    };

    return @ptrCast(ctx.target_canvas.data);
}

/// Evaluate best solution
export fn pale_evaluate_best_solution(context: ?*Context) u64 {
    const ctx = context orelse {
        std.log.err("Passed context is null", .{});
        return 0;
    };

    _ = ctx.best_solution.eval(&ctx.target_canvas, &ctx.best_canvas) catch {
        std.log.err("Error evaluating solution", .{});
        return 0;
    };

    return ctx.best_solution.fitness.evaluated.pixelError;
}

/// Get image
export fn pale_get_best_image(context: ?*Context) ?[*]const u8 {
    const ctx = context orelse {
        std.log.err("Passed context is null", .{});
        return null;
    };

    return @ptrCast(ctx.best_canvas.data);
}

/// Get total iterations
export fn pale_get_iterations(context: ?*Context) u64 {
    const ctx = context orelse {
        std.log.err("Passed context is null", .{});
        return 0;
    };

    if (ctx.iteration_count == 0) {
        std.log.err("The program has not been run yet", .{});
        return 0;
    }

    return ctx.iteration_count;
}
