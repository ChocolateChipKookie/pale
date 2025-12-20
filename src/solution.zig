const std = @import("std");
const graphics = @import("graphics.zig");
const Canvas = graphics.Canvas;
const Color = graphics.Color;
const Rectangle = graphics.Rectangle;

pub const ColoredRectangle = struct {
    rect: Rectangle,
    color: Color,
};

pub const Fitness = struct {
    const solutionPenalty = 200;
    // Total pixel difference over the whole image
    // Dominates the total error calculation, also main driving factor
    pixelError: u64,
    // Number of rectangles in solution
    // Nudges toward deleting useless rectangles, multiplied with penalty
    // factor to also delete very small rectangles
    size: u64,
    // Total area should always be smaller then solution penalty assuming
    // that the max error per pixel is 3 * 255 and
    // Only case where this might not be the case is if there is a lot of
    // overlayed rectangles, which is undesireable anyways
    // NOTE: this assumes full opacity, calcultion might be different for
    //       non-opaque rectangles
    totalArea: u64,

    pub fn total(self: Fitness) u64 {
        return self.pixelError + self.size * solutionPenalty + self.totalArea;
    }
};

pub const Solution = struct {
    data: std.ArrayList(ColoredRectangle),
    fitness: union(enum) {
        unevaluated: Rectangle,
        evaluated: Fitness,
    },

    pub fn init(alloc: std.mem.Allocator, capacity: usize, image_width: usize, image_height: usize) !Solution {
        const data = try std.ArrayList(ColoredRectangle).initCapacity(alloc, capacity);
        return Solution{
            .data = data,
            .fitness = .{
                .unevaluated = .{
                    .x = 0,
                    .y = 0,
                    .width = @intCast(image_width),
                    .height = @intCast(image_height),
                },
            },
        };
    }
    pub fn deinit(self: *Solution, alloc: std.mem.Allocator) void {
        self.data.deinit(alloc);
    }

    pub fn clone(self: *Solution, alloc: std.mem.Allocator) !Solution {
        const data = try self.data.clone(alloc);
        return Solution{
            .data = data,
            .fitness = self.fitness,
        };
    }

    pub fn cloneIntoAssumingCapacity(self: *Solution, other: *Solution) void {
        other.data.clearRetainingCapacity();
        other.data.appendSliceAssumeCapacity(self.data.items);
        other.fitness = self.fitness;
    }

    pub fn addUnevaluated(self: *Solution, rect: Rectangle) void {
        if (self.fitness == .evaluated) {
            self.fitness = .{ .unevaluated = rect };
        } else {
            const xStart1 = self.fitness.unevaluated.x;
            const xEnd1 = xStart1 + self.fitness.unevaluated.width;
            const xStart2 = rect.x;
            const xEnd2 = xStart2 + rect.width;

            const yStart1 = self.fitness.unevaluated.y;
            const yEnd1 = yStart1 + self.fitness.unevaluated.height;
            const yStart2 = rect.y;
            const yEnd2 = yStart2 + rect.height;

            const minX = @min(xStart1, xStart2);
            const maxX = @max(xEnd1, xEnd2);
            const minY = @min(yStart1, yStart2);
            const maxY = @max(yEnd1, yEnd2);

            self.fitness.unevaluated = .{
                .x = minX,
                .y = minY,
                .width = maxX - minX,
                .height = maxY - minY,
            };
        }
    }

    pub fn maxError(width: usize, height: usize) u64 {
        return @intCast(width * height * 256 * 3);
    }

    pub fn draw(self: Solution, canvas: *Canvas) void {
        self.drawRegion(canvas, .{
            .x = 0,
            .y = 0,
            .width = @intCast(canvas.width),
            .height = @intCast(canvas.height),
        });
    }

    pub fn drawRegion(self: Solution, canvas: *Canvas, region: Rectangle) void {
        // canvas.clearBackground is for some reason a lot less performant than just drawing a black rectangle
        canvas.drawRectangle(region, .black);

        for (self.data.items) |coloredRect| {
            const rect = coloredRect.rect;
            if (!region.intersects(rect)) {
                continue;
            }
            canvas.drawRectangle(rect, coloredRect.color);
        }
    }

    pub fn eval(self: *Solution, target: *const Canvas, canvas: *Canvas) !u64 {
        if (target.width != canvas.width) {
            return error.InvalidArgument;
        }
        if (target.width != canvas.width) {
            return error.InvalidArgument;
        }

        var totalArea: u64 = 0;
        for (self.data.items) |rect| {
            totalArea += @intCast(rect.rect.height * rect.rect.width);
        }

        self.draw(canvas);

        var pixelError: u64 = 0;
        for (target.data, canvas.data) |targetPixel, canvasPixel| {
            const targetR: i64 = @intCast(targetPixel.r);
            const canvasR: i64 = @intCast(canvasPixel.r);
            pixelError += @abs(targetR - canvasR);
            const targetG: i64 = @intCast(targetPixel.g);
            const canvasG: i64 = @intCast(canvasPixel.g);
            pixelError += @abs(targetG - canvasG);
            const targetB: i64 = @intCast(targetPixel.b);
            const canvasB: i64 = @intCast(canvasPixel.b);
            pixelError += @abs(targetB - canvasB);
        }
        self.fitness = .{ .evaluated = .{
            .pixelError = pixelError,
            .size = self.data.items.len,
            .totalArea = totalArea,
        } };
        return self.fitness.evaluated.total();
    }

    pub fn evalRegion(self: *Solution, target_canvas: *const Canvas, parent: Solution, parent_canvas: *Canvas, test_canvas: *Canvas) !u64 {
        if (target_canvas.width != test_canvas.width or target_canvas.width != parent_canvas.width) {
            std.log.err("Image widths don't match up", .{});
            return error.InvalidArgument;
        }
        if (target_canvas.height != test_canvas.height or target_canvas.height != parent_canvas.height) {
            std.log.err("Image heights don't match up", .{});
            return error.InvalidArgument;
        }

        if (self.fitness == .evaluated) {
            return self.fitness.evaluated.total();
        }
        if (parent.fitness != .evaluated) {
            std.log.err("Parent is not evaluated", .{});
            return error.InvalidArgument;
        }

        var totalArea: u64 = 0;
        for (self.data.items) |rect| {
            totalArea += @intCast(rect.rect.height * rect.rect.width);
        }

        self.drawRegion(test_canvas, self.fitness.unevaluated);

        var totalParent: u64 = 0;
        var totalChild: u64 = 0;

        const colors_target: []Color = target_canvas.data;
        const colors_parent: []Color = parent_canvas.data;
        const colors_canvas: []Color = test_canvas.data;

        const uneval = self.fitness.unevaluated;

        const xStart = @max(0, @min(uneval.x, test_canvas.width));
        const xEnd = @max(0, @min(uneval.x + uneval.width, test_canvas.width));
        var y = @max(0, @min(uneval.y, test_canvas.height));
        const yEnd = @max(0, @min(uneval.y + uneval.height, test_canvas.height));

        while (y < yEnd) : (y += 1) {
            const iStart: usize = @intCast(y * test_canvas.width + xStart);
            const iEnd: usize = iStart + (xEnd - xStart);
            for (colors_target[iStart..iEnd], colors_canvas[iStart..iEnd], colors_parent[iStart..iEnd]) |target_pixel, canvas_pixel, parent_pixel| {
                const targetR: i64 = @intCast(target_pixel.r);
                const canvasR: i64 = @intCast(canvas_pixel.r);
                const parentR: i64 = @intCast(parent_pixel.r);
                totalParent += @abs(targetR - parentR);
                totalChild += @abs(targetR - canvasR);
                const targetG: i64 = @intCast(target_pixel.g);
                const canvasG: i64 = @intCast(canvas_pixel.g);
                const parentG: i64 = @intCast(parent_pixel.g);
                totalParent += @abs(targetG - parentG);
                totalChild += @abs(targetG - canvasG);
                const targetB: i64 = @intCast(target_pixel.b);
                const canvasB: i64 = @intCast(canvas_pixel.b);
                const parentB: i64 = @intCast(parent_pixel.b);
                totalParent += @abs(targetB - parentB);
                totalChild += @abs(targetB - canvasB);
            }
        }

        const pixelError = parent.fitness.evaluated.pixelError - totalParent + totalChild;

        self.fitness = .{ .evaluated = .{
            .pixelError = pixelError,
            .size = self.data.items.len,
            .totalArea = totalArea,
        } };
        return self.fitness.evaluated.total();
    }
};
