const rl = @import("raylib");
const std = @import("std");

pub const Rectangle = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,

    pub fn intersects(self: Rectangle, other: Rectangle) bool {
        return self.x <= other.x + other.width and
            self.x + self.width >= other.x and
            self.y <= other.y + other.height and
            self.y + self.height >= other.y;
    }
};

pub const ColoredRectangle = struct {
    rect: Rectangle,
    color: rl.Color,
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

    pub fn init(alloc: std.mem.Allocator, capacity: usize, imageWidth: i32, imageHeight: i32) !Solution {
        const data = try std.ArrayList(ColoredRectangle).initCapacity(alloc, capacity);
        return Solution{
            .data = data,
            .fitness = .{
                .unevaluated = .{
                    .x = 0,
                    .y = 0,
                    .width = imageWidth,
                    .height = imageHeight,
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

    pub fn maxError(width: i32, height: i32) u64 {
        return @intCast(width * height * 256 * 3);
    }

    pub fn draw(self: Solution, canvas: *rl.Image) void {
        self.drawRegion(canvas, .{
            .x = 0,
            .y = 0,
            .width = canvas.width,
            .height = canvas.height,
        });
    }

    pub fn drawRegion(self: Solution, canvas: *rl.Image, region: Rectangle) void {
        // canvas.clearBackground is for some reason a lot less performant than just drawing a black rectangle
        canvas.drawRectangle(region.x, region.y, region.width, region.height, .black);

        for (self.data.items) |coloredRect| {
            const rect = coloredRect.rect;
            if (!region.intersects(rect)) {
                continue;
            }
            canvas.drawRectangle(rect.x, rect.y, rect.width, rect.height, coloredRect.color);
        }
    }

    pub fn eval(self: *Solution, target: *rl.Image, canvas: *rl.Image) !u64 {
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

        const colorsTarget = try rl.loadImageColors(target.*);
        defer rl.unloadImageColors(colorsTarget);
        const colorsCanvas = try rl.loadImageColors(canvas.*);
        defer rl.unloadImageColors(colorsCanvas);

        var pixelError: u64 = 0;
        for (colorsTarget, colorsCanvas) |targetPixel, canvasPixel| {
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

    pub fn evalRegion(self: *Solution, target: *rl.Image, parent: Solution, parentImage: *rl.Image, canvas: *rl.Image) !u64 {
        if (target.width != canvas.width or target.width != parentImage.width) {
            std.log.err("Image widths don't match up", .{});
            return error.InvalidArgument;
        }
        if (target.height != canvas.height or target.height != parentImage.height) {
            std.log.err("Image heights don't match up", .{});
            return error.InvalidArgument;
        }

        const expectedFormat = rl.PixelFormat.uncompressed_r8g8b8a8;
        if (target.format != expectedFormat or parentImage.format != expectedFormat or canvas.format != expectedFormat) {
            std.log.err("Expected all the input images to have format {}", .{expectedFormat});
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

        self.drawRegion(canvas, self.fitness.unevaluated);

        var totalParent: u64 = 0;
        var totalChild: u64 = 0;

        const colorsTarget: [*]rl.Color = @ptrCast(@alignCast(target.data));
        const colorsParent: [*]rl.Color = @ptrCast(@alignCast(parentImage.data));
        const colorsCanvas: [*]rl.Color = @ptrCast(@alignCast(canvas.data));

        const uneval = self.fitness.unevaluated;

        const xStart = @max(0, @min(uneval.x, canvas.width));
        const xEnd = @max(0, @min(uneval.x + uneval.width, canvas.width));
        var y = @max(0, @min(uneval.y, canvas.height));
        const yEnd = @max(0, @min(uneval.y + uneval.height, canvas.height));

        while (y < yEnd) : (y += 1) {
            const iStart: usize = @intCast(y * canvas.width + xStart);
            const iEnd: usize = iStart + (xEnd - xStart);
            for (colorsTarget[iStart..iEnd], colorsCanvas[iStart..iEnd], colorsParent[iStart..iEnd]) |targetPixel, canvasPixel, parentPixel| {
                const targetR: i64 = @intCast(targetPixel.r);
                const canvasR: i64 = @intCast(canvasPixel.r);
                const parentR: i64 = @intCast(parentPixel.r);
                totalParent += @abs(targetR - parentR);
                totalChild += @abs(targetR - canvasR);
                const targetG: i64 = @intCast(targetPixel.g);
                const canvasG: i64 = @intCast(canvasPixel.g);
                const parentG: i64 = @intCast(parentPixel.g);
                totalParent += @abs(targetG - parentG);
                totalChild += @abs(targetG - canvasG);
                const targetB: i64 = @intCast(targetPixel.b);
                const canvasB: i64 = @intCast(canvasPixel.b);
                const parentB: i64 = @intCast(parentPixel.b);
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
