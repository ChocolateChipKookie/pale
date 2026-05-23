const std = @import("std");
const exports = @import("wasm_exports.zig");

test "full export cycle on a small canvas" {
    const alloc = std.testing.allocator;

    const ctx = exports.pale_create(&alloc, 32, 32, 100, 42) orelse
        return error.PaleCreateFailed;
    defer std.debug.assert(exports.pale_destroy(&alloc, ctx));

    try std.testing.expect(exports.pale_get_target_image(ctx) != null);
    try std.testing.expect(exports.pale_get_best_image(ctx) != null);

    _ = exports.pale_run_steps(ctx, 16);
    _ = exports.pale_evaluate_best_solution(ctx);

    try std.testing.expect(exports.pale_get_iterations(ctx) > 0);
}

test "null-context handling" {
    const alloc = std.testing.allocator;

    try std.testing.expectEqual(false, exports.pale_destroy(&alloc, null));
    try std.testing.expectEqual(@as(u64, 0), exports.pale_run_steps(null, 1));
    try std.testing.expect(exports.pale_get_target_image(null) == null);
    try std.testing.expect(exports.pale_get_best_image(null) == null);
    try std.testing.expectEqual(@as(u64, 0), exports.pale_evaluate_best_solution(null));
    try std.testing.expectEqual(@as(u64, 0), exports.pale_get_iterations(null));
}

test "pale_get_allocator returns a non-null pointer" {
    const ptr = exports.pale_get_allocator();
    try std.testing.expect(@intFromPtr(ptr) != 0);
}
