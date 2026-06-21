const std = @import("std");
const exports = @import("wasm_exports.zig");

test "full export cycle on a small canvas" {
    const alloc = std.testing.allocator;

    const ctx = exports.pale_create(&alloc, 32, 32, 100, 42, 0) orelse
        return error.PaleCreateFailed;
    defer std.debug.assert(exports.pale_destroy(&alloc, ctx));

    try std.testing.expect(exports.pale_get_target_image(ctx) != null);
    try std.testing.expect(exports.pale_get_best_image(ctx) != null);

    _ = exports.pale_run_steps(ctx, 16);
    _ = exports.pale_evaluate_best_solution(ctx);

    try std.testing.expectEqual(@as(u64, 16), exports.pale_get_iterations(ctx));
    try std.testing.expect(exports.pale_get_rectangle_count(ctx) <= 100);
}

test "null-context handling" {
    const alloc = std.testing.allocator;

    try std.testing.expectEqual(false, exports.pale_destroy(&alloc, null));
    try std.testing.expectEqual(@as(u64, 0), exports.pale_run_steps(null, 1));
    try std.testing.expect(exports.pale_get_target_image(null) == null);
    try std.testing.expect(exports.pale_get_best_image(null) == null);
    try std.testing.expectEqual(@as(u64, 0), exports.pale_evaluate_best_solution(null));
    try std.testing.expectEqual(@as(u64, 0), exports.pale_get_iterations(null));
    try std.testing.expectEqual(@as(u32, 0), exports.pale_get_rectangle_count(null));
}

test "pale_get_allocator returns a non-null pointer" {
    const ptr = exports.pale_get_allocator();
    try std.testing.expect(@intFromPtr(ptr) != 0);
}

test "iteration counter resets across context lifecycles" {
    const alloc = std.testing.allocator;

    const first = exports.pale_create(&alloc, 32, 32, 100, 1, 0) orelse
        return error.PaleCreateFailed;
    _ = exports.pale_run_steps(first, 16);
    try std.testing.expectEqual(@as(u64, 16), exports.pale_get_iterations(first));
    std.debug.assert(exports.pale_destroy(&alloc, first));

    const second = exports.pale_create(&alloc, 32, 32, 100, 2, 0) orelse
        return error.PaleCreateFailed;
    defer std.debug.assert(exports.pale_destroy(&alloc, second));
    _ = exports.pale_run_steps(second, 4);
    try std.testing.expectEqual(@as(u64, 4), exports.pale_get_iterations(second));
}
