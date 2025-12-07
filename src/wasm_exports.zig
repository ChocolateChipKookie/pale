const std = @import("std");
const rl = @import("raylib");
const Solution = @import("solution.zig").Solution;
const CombinedMutation = @import("mutation.zig").CombinedMutation;

const allocator = std.heap.c_allocator;

/// Global state for the optimization context
const Context = struct {
    target_image: rl.Image,
    best_canvas: rl.Image,
    test_canvas: rl.Image,
    best_solution: Solution,
    test_solution: Solution,
    mutation: CombinedMutation,
    prng: std.Random.DefaultPrng,
    iteration_count: u64,
};

var global_context: ?*Context = null;

/// Creates a new optimization context.
/// Takes raw RGBA pixel data from JavaScript (data is copied).
/// Returns null on success, or an error message string on failure.
export fn pale_create(
    target_pixels: [*]const u8,
    width: i32,
    height: i32,
    capacity: u32,
    seed: u64,
) ?[*:0]const u8 {
    if (global_context != null) {
        return "Context already initialized";
    }

    const ctx = allocator.create(Context) catch return "Failed to allocate context";

    // Copy target image data
    const pixel_count: usize = @intCast(width * height);
    const pixel_data = allocator.alloc(rl.Color, pixel_count) catch {
        allocator.destroy(ctx);
        return "Failed to allocate target image data";
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
    const rng = ctx.prng.random();

    // Initialize solutions
    ctx.best_solution = Solution.init(allocator, capacity, width, height) catch {
        allocator.free(pixel_data);
        rl.unloadImage(ctx.best_canvas);
        rl.unloadImage(ctx.test_canvas);
        allocator.destroy(ctx);
        return "Failed to allocate best solution";
    };

    _ = ctx.best_solution.eval(&ctx.target_image, &ctx.best_canvas) catch {
        ctx.best_solution.deinit(allocator);
        allocator.free(pixel_data);
        rl.unloadImage(ctx.best_canvas);
        rl.unloadImage(ctx.test_canvas);
        allocator.destroy(ctx);
        return "Failed to evaluate initial solution";
    };

    ctx.test_solution = ctx.best_solution.clone(allocator) catch {
        ctx.best_solution.deinit(allocator);
        allocator.free(pixel_data);
        rl.unloadImage(ctx.best_canvas);
        rl.unloadImage(ctx.test_canvas);
        allocator.destroy(ctx);
        return "Failed to clone test solution";
    };

    ctx.mutation = CombinedMutation.init(&rng, width, height);
    ctx.iteration_count = 0;

    global_context = ctx;
    return null;
}

/// Destroys the optimization context and frees all resources.
export fn pale_destroy() void {
    const ctx = global_context orelse return;

    ctx.best_solution.deinit(allocator);
    ctx.test_solution.deinit(allocator);

    // Free the copied target image data
    const pixel_count: usize = @intCast(ctx.target_image.width * ctx.target_image.height);
    const pixel_data: [*]rl.Color = @ptrCast(@alignCast(ctx.target_image.data));
    allocator.free(pixel_data[0..pixel_count]);

    rl.unloadImage(ctx.best_canvas);
    rl.unloadImage(ctx.test_canvas);

    allocator.destroy(ctx);
    global_context = null;
}
