const std = @import("std");
const rl = @import("raylib");

const Error = error{InvalidArgument};

const Rectangle = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,

    pub fn intersects(self: Rectangle, other: Rectangle) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }
};

const ColoredRectangle = struct {
    rect: Rectangle,
    color: rl.Color = .white,
};

const Solution = struct {
    data: std.ArrayList(ColoredRectangle),
    fitness: union(enum) {
        unevaluated: Rectangle,
        evaluated: u64,
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
        canvas.clearBackground(.black);
        for (self.data.items) |coloredRect| {
            const rect = coloredRect.rect;
            canvas.drawRectangle(rect.x, rect.y, rect.width, rect.height, coloredRect.color);
        }
    }

    pub fn drawRegion(self: Solution, canvas: *rl.Image, region: Rectangle) void {
        canvas.clearBackground(.black);
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

        self.draw(canvas);
        var total: u64 = 0;

        const colorsTarget = try rl.loadImageColors(target.*);
        defer rl.unloadImageColors(colorsTarget);
        const colorsCanvas = try rl.loadImageColors(canvas.*);
        defer rl.unloadImageColors(colorsCanvas);

        for (colorsTarget, colorsCanvas) |targetPixel, canvasPixel| {
            const targetR: i64 = @intCast(targetPixel.r);
            const canvasR: i64 = @intCast(canvasPixel.r);
            total += @abs(targetR - canvasR);
            const targetG: i64 = @intCast(targetPixel.g);
            const canvasG: i64 = @intCast(canvasPixel.g);
            total += @abs(targetG - canvasG);
            const targetB: i64 = @intCast(targetPixel.b);
            const canvasB: i64 = @intCast(canvasPixel.b);
            total += @abs(targetB - canvasB);
        }
        self.fitness = .{ .evaluated = total };
        return total;
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
            return self.fitness.evaluated;
        }
        if (parent.fitness != .evaluated) {
            std.log.err("Parent is not evaluated", .{});
            return error.InvalidArgument;
        }
        self.drawRegion(canvas, self.fitness.unevaluated);

        var totalParent: u64 = 0;
        var totalChild: u64 = 0;

        const colorsTarget: [*]rl.Color = @ptrCast(@alignCast(target.data));
        const colorsParent: [*]rl.Color = @ptrCast(@alignCast(parentImage.data));
        const colorsCanvas: [*]rl.Color = @ptrCast(@alignCast(canvas.data));

        const uneval = self.fitness.unevaluated;

        const xStart = @max(0, @min(uneval.x, canvas.width - 1));
        const xEnd = @max(0, @min(uneval.x + uneval.width, canvas.width - 1));
        var y = @max(0, @min(uneval.y, canvas.height - 1));
        const yEnd = @max(0, @min(uneval.y + uneval.height, canvas.height - 1));

        while (y <= yEnd) : (y += 1) {
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

        self.fitness = .{ .evaluated = parent.fitness.evaluated - totalParent + totalChild };
        return self.fitness.evaluated;
    }
};

const AddMutation = struct {
    rng: *const std.Random,
    imageWidth: i32,
    imageHeight: i32,

    pub fn init(rng: *const std.Random, imageWidth: i32, imageHeight: i32) AddMutation {
        return AddMutation{
            .rng = rng,
            .imageWidth = imageWidth,
            .imageHeight = imageHeight,
        };
    }

    pub fn mutate(self: AddMutation, solution: *Solution) void {
        std.log.debug("Add mutation", .{});

        const sizeRange = 100;
        const x = self.rng.intRangeAtMost(i32, 0, self.imageWidth);
        const y = self.rng.intRangeAtMost(i32, 0, self.imageHeight);
        const dx = self.rng.intRangeAtMost(i32, -sizeRange, sizeRange);
        const dy = self.rng.intRangeAtMost(i32, -sizeRange, sizeRange);
        var color = rl.Color.fromInt(self.rng.int(u32));
        color.a = 255;

        const rect: Rectangle = .{
            .x = @min(x, x + dx),
            .y = @min(y, y + dy),
            .width = @intCast(@abs(dx)),
            .height = @intCast(@abs(dy)),
        };
        solution.addUnevaluated(rect);

        if (solution.*.data.capacity == solution.*.data.items.len) {
            const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);
            solution.addUnevaluated(solution.data.items[index].rect);
            solution.*.data.items[index] = .{
                .rect = rect,
                .color = color,
            };
        } else {
            const index = self.rng.intRangeAtMost(usize, 0, solution.*.data.items.len);
            solution.*.data.insertAssumeCapacity(index, .{
                .rect = rect,
                .color = color,
            });
        }
    }
};

const MoveMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) MoveMutation {
        var res = MoveMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(self: MoveMutation, solution: *Solution) void {
        if (solution.*.data.items.len == 0) {
            return;
        }
        std.log.debug("Move mutation", .{});
        const diffRange = 20;
        const dx = self.rng.intRangeAtMost(i32, -diffRange, diffRange);
        const dy = self.rng.intRangeAtMost(i32, -diffRange, diffRange);
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);

        solution.addUnevaluated(solution.*.data.items[index].rect);
        solution.*.data.items[index].rect.x += dx;
        solution.*.data.items[index].rect.y += dy;
        solution.addUnevaluated(solution.*.data.items[index].rect);
    }
};

const ResizeMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ResizeMutation {
        var res = ResizeMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(self: ResizeMutation, solution: *Solution) void {
        if (solution.*.data.items.len == 0) {
            return;
        }
        std.log.debug("Resize mutation", .{});
        const dx = self.rng.intRangeAtMost(i32, -10, 10);
        const dy = self.rng.intRangeAtMost(i32, -10, 10);
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);

        const rect = &solution.data.items[index].rect;
        solution.addUnevaluated(rect.*);
        rect.width = @max(1, rect.width + dx);
        rect.height = @max(1, rect.height + dy);
        solution.addUnevaluated(rect.*);
    }
};

const ColorMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ColorMutation {
        var res = ColorMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(self: ColorMutation, solution: *Solution) void {
        if (solution.*.data.items.len == 0) {
            return;
        }
        std.log.debug("Resize mutation", .{});
        const colorDiffRange = 50;
        const dr = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const dg = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const db = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);

        const item = &solution.*.data.items[index];
        solution.addUnevaluated(item.rect);
        item.color.r = @intCast(@mod(@as(i32, item.color.r) + dr, 256));
        item.color.g = @intCast(@mod(@as(i32, item.color.g) + dg, 256));
        item.color.b = @intCast(@mod(@as(i32, item.color.b) + db, 256));
    }
};

const MutationUnion = union(enum) {
    add: AddMutation,
    move: MoveMutation,
    color: ColorMutation,
    resize: ResizeMutation,

    pub fn mutate(self: MutationUnion, solution: *Solution) void {
        switch (self) {
            inline else => |case| return case.mutate(solution),
        }
    }
};

const CombinedMutation = struct {
    mutations: [4]MutationUnion,
    weights: [4]i32,
    rng: *const std.Random,

    pub fn init(rng: *const std.Random, imageWidth: i32, imageHeight: i32) CombinedMutation {
        return CombinedMutation{
            .rng = rng,
            .mutations = .{
                .{
                    .add = AddMutation.init(
                        rng,
                        imageWidth,
                        imageHeight,
                    ),
                },
                .{
                    .color = ColorMutation.init(rng),
                },
                .{
                    .move = MoveMutation.init(rng),
                },
                .{
                    .resize = ResizeMutation.init(rng),
                },
            },
            .weights = .{
                10, 10, 10, 10,
            },
        };
    }

    pub fn mutate(self: CombinedMutation, solution: *Solution) void {
        const index = self.rng.weightedIndex(i32, &self.weights);
        self.mutations[index].mutate(solution);
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var targetImage = try rl.Image.init("earring.png");
    defer targetImage.unload();
    if (targetImage.format != rl.PixelFormat.uncompressed_r8g8b8a8) {
        rl.imageFormat(&targetImage, rl.PixelFormat.uncompressed_r8g8b8a8);
    }

    std.log.info("Image size: {d}x{d}", .{ targetImage.width, targetImage.height });

    var bestCanvasImage = targetImage.copy();
    defer bestCanvasImage.unload();

    var canvasImage = targetImage.copy();
    defer canvasImage.unload();

    rl.setTraceLogLevel(.err);
    rl.initWindow(targetImage.width, targetImage.height, "Pale");
    defer rl.closeWindow();

    const texture = try rl.Texture2D.fromImage(canvasImage);
    defer texture.unload();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rng = prng.random();

    var bestSolution = Solution.init(alloc, 100, targetImage.width, targetImage.height) catch |err| {
        std.log.err("Error allocating solution ({}), exiting!", .{err});
        return;
    };
    defer bestSolution.deinit(alloc);
    _ = try bestSolution.eval(&targetImage, &canvasImage);
    var testSolution = try bestSolution.clone(alloc);
    defer testSolution.deinit(alloc);

    const mutation = CombinedMutation.init(&rng, targetImage.width, targetImage.height);

    var buffer: [64]u8 = undefined;
    var counter: i32 = 0;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const start = std.time.microTimestamp();
    const totalTime = std.time.us_per_min;

    const targetFps = 30;
    const targetFrameDurationMicro = std.time.us_per_s / targetFps;

    while (!rl.windowShouldClose()) {
        const frameStart = std.time.microTimestamp();
        if (frameStart - start > totalTime) {
            break;
        }

        // Update
        while (frameStart + targetFrameDurationMicro > std.time.microTimestamp()) {
            counter += 1;
            bestSolution.cloneIntoAssumingCapacity(&testSolution);
            mutation.mutate(&testSolution);

            _ = try testSolution.evalRegion(&targetImage, bestSolution, &bestCanvasImage, &canvasImage);
            if (testSolution.fitness.evaluated <= bestSolution.fitness.evaluated) {
                testSolution.cloneIntoAssumingCapacity(&bestSolution);
                testSolution.draw(&bestCanvasImage);
                rl.updateTexture(texture, bestCanvasImage.data);
            }
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);
        rl.drawTexture(texture, 0, 0, .white);

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Counter: {}", .{counter});
            rl.drawText(text, 10, 10, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "Fitness: {}", .{bestSolution.fitness.evaluated});
            rl.drawText(text, 10, 40, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "FPS:     {}", .{rl.getFPS()});
            rl.drawText(text, 10, 70, 20, .light_gray);
        }

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Rects:   {}", .{bestSolution.data.items.len});
            rl.drawText(text, 10, 100, 20, .light_gray);
        }
    }

    const end = std.time.microTimestamp();
    const totalSeconds = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    try stdout.print("Iterations: {}\n", .{counter});
    try stdout.print("Seconds: {}\n", .{totalSeconds});
    try stdout.print("Iters/second: {}\n", .{@as(f64, @floatFromInt(counter)) / totalSeconds});
    try stdout.print("Normalized error: {}\n", .{@as(f64, @floatFromInt(bestSolution.fitness.evaluated)) / @as(f64, @floatFromInt(Solution.maxError(targetImage.width, targetImage.height)))});
    try stdout.flush();

    _ = bestCanvasImage.exportToFile("out.png");
}
