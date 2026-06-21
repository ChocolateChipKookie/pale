const std = @import("std");
const rl = @import("raylib");

const Config = struct {
    out_dir: []const u8,
    thumb: i32,
    max_dim: i32,
    inputs: []const [:0]const u8,
};

fn parseArgs(raw: []const [:0]const u8) !Config {
    if (raw.len < 4) {
        std.log.err("usage: thumbnail <out_dir> <thumb_size> <max_dim> <input>...", .{});
        return error.BadArgs;
    }
    return .{
        .out_dir = raw[1],
        .thumb = try std.fmt.parseInt(i32, raw[2], 10),
        .max_dim = try std.fmt.parseInt(i32, raw[3], 10),
        .inputs = raw[4..],
    };
}

/// Bounds the longest side to max_dim, preserving aspect ratio. Never upscales.
fn boundedSize(width: i32, height: i32, max_dim: i32) struct { w: i32, h: i32 } {
    const longest = @max(width, height);
    if (longest <= max_dim) return .{ .w = width, .h = height };
    const scale = @as(f64, @floatFromInt(max_dim)) / @as(f64, @floatFromInt(longest));
    return .{
        .w = @intFromFloat(@round(@as(f64, @floatFromInt(width)) * scale)),
        .h = @intFromFloat(@round(@as(f64, @floatFromInt(height)) * scale)),
    };
}

fn processImage(
    alloc: std.mem.Allocator,
    cfg: Config,
    in_path: [:0]const u8,
) !void {
    const stem = std.fs.path.stem(in_path);

    const image = rl.Image.init(in_path) catch {
        std.log.warn("skipping (failed to load): {s}", .{in_path});
        return;
    };
    defer rl.unloadImage(image);

    // Resized full version: longest side bounded to max_dim, aspect preserved.
    {
        var full = rl.imageCopy(image);
        defer rl.unloadImage(full);
        const size = boundedSize(full.width, full.height, cfg.max_dim);
        rl.imageResize(&full, size.w, size.h);
        const path = try std.fmt.allocPrintSentinel(alloc, "{s}/{s}.png", .{ cfg.out_dir, stem }, 0);
        defer alloc.free(path);
        if (!rl.exportImage(full, path)) std.log.err("failed to write {s}", .{path});
    }

    // Thumbnail: center-crop to a square, then resize (no distortion).
    {
        var thumb = rl.imageCopy(image);
        defer rl.unloadImage(thumb);
        const side = @min(thumb.width, thumb.height);
        rl.imageCrop(&thumb, .{
            .x = @floatFromInt(@divTrunc(thumb.width - side, 2)),
            .y = @floatFromInt(@divTrunc(thumb.height - side, 2)),
            .width = @floatFromInt(side),
            .height = @floatFromInt(side),
        });
        rl.imageResize(&thumb, cfg.thumb, cfg.thumb);
        const path = try std.fmt.allocPrintSentinel(alloc, "{s}/{s}.thumb.png", .{ cfg.out_dir, stem }, 0);
        defer alloc.free(path);
        if (!rl.exportImage(thumb, path)) std.log.err("failed to write {s}", .{path});
    }
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    const raw = try init.minimal.args.toSlice(alloc);
    const cfg = try parseArgs(raw);

    rl.setTraceLogLevel(.warning);

    for (cfg.inputs) |in_path| {
        try processImage(alloc, cfg, in_path);
    }
}
