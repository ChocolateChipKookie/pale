const std = @import("std");
const rl = @import("raylib");

const Error = error{InvalidArgument};

const Rectangle = struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    color: rl.Color = .white,
};

const Solution = struct {
    data: std.ArrayList(Rectangle),

    pub fn init(alloc: std.mem.Allocator, capacity: usize) !Solution {
        const data = try std.ArrayList(Rectangle).initCapacity(alloc, capacity);
        return Solution{ .data = data };
    }
    pub fn deinit(self: *Solution, alloc: std.mem.Allocator) void {
        self.data.deinit(alloc);
    }

    pub fn clone(self: *Solution, alloc: std.mem.Allocator) !Solution {
        const data = try self.data.clone(alloc);
        return Solution{ .data = data };
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
        const color = rl.Color.fromInt(self.rng.int(u32));

        if (solution.*.data.capacity == solution.*.data.items.len) {
            const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);
            solution.*.data.items[index] = .{
                .x = @min(x, x + dx),
                .y = @min(y, y + dy),
                .width = @intCast(@abs(dx)),
                .height = @intCast(@abs(dy)),
                .color = color,
            };
        } else {
            const index = self.rng.intRangeAtMost(usize, 0, solution.*.data.items.len);
            solution.*.data.insertAssumeCapacity(index, .{
                .x = @min(x, x + dx),
                .y = @min(y, y + dy),
                .width = @intCast(@abs(dx)),
                .height = @intCast(@abs(dy)),
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
        const dx = self.rng.intRangeAtMost(i32, -20, 20);
        const dy = self.rng.intRangeAtMost(i32, -20, 20);
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);

        solution.*.data.items[index].x += dx;
        solution.*.data.items[index].y += dy;
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

        const item = &solution.*.data.items[index];
        item.width = @max(1, item.width + dx);
        item.height = @max(1, item.height + dy);
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
    const WeightedMutation = struct { weight: i32, mutation: MutationUnion };
    mutations: [4]WeightedMutation,
    rng: *const std.Random,

    pub fn init(rng: *const std.Random, imageWidth: i32, imageHeight: i32) CombinedMutation {
        return CombinedMutation{
            .rng = rng,
            .mutations = .{
                .{
                    .weight = 1,
                    .mutation = MutationUnion{ .add = AddMutation.init(
                        rng,
                        imageWidth,
                        imageHeight,
                    ) },
                },
                .{
                    .weight = 1,
                    .mutation = MutationUnion{
                        .color = ColorMutation.init(rng),
                    },
                },
                .{
                    .weight = 1,
                    .mutation = MutationUnion{
                        .move = MoveMutation.init(rng),
                    },
                },
                .{
                    .weight = 1,
                    .mutation = MutationUnion{
                        .resize = ResizeMutation.init(rng),
                    },
                },
            },
        };
    }

    pub fn mutate(self: CombinedMutation, solution: *Solution) void {
        const index = self.rng.intRangeLessThan(usize, 0, self.mutations.len);
        self.mutations[index].mutation.mutate(solution);
    }
};

fn DrawSolution(solution: *const Solution, canvas: *rl.Image) !void {
    canvas.clearBackground(.black);
    for (solution.data.items) |rect| {
        canvas.drawRectangle(rect.x, rect.y, rect.width, rect.height, rect.color);
    }
}

fn EvalImageNaive(target: *const rl.Image, canvas: *rl.Image, solution: *const Solution) !u64 {
    try DrawSolution(solution, canvas);
    var total: u64 = @intCast(solution.data.items.len);

    if (target.width != canvas.width) {
        return error.InvalidArgument;
    }
    if (target.width != canvas.width) {
        return error.InvalidArgument;
    }

    for (0..@intCast(target.height)) |y| {
        for (0..@intCast(target.width)) |x| {
            const targetPixel = target.getColor(@intCast(x), @intCast(y));
            const canvasPixel = canvas.getColor(@intCast(x), @intCast(y));
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
    }
    return total;
}

fn EvalImageNaiveLoadColors(target: *const rl.Image, canvas: *rl.Image, solution: *const Solution) !u64 {
    try DrawSolution(solution, canvas);

    var total: u64 = @intCast(solution.data.items.len);

    if (target.width != canvas.width) {
        return error.InvalidArgument;
    }
    if (target.width != canvas.width) {
        return error.InvalidArgument;
    }

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
    return total;
}

pub fn main() anyerror!void {
    rl.setTraceLogLevel(.err);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var solution = Solution.init(alloc, 100) catch |err| {
        std.log.err("Error allocating solution ({}), exiting!", .{err});
        return;
    };
    defer solution.deinit(alloc);

    var targetImage = try rl.Image.init("earring.png");
    // rl.imageColorGrayscale(&targetImage);
    defer targetImage.unload();
    std.log.info("Image size: {d}x{d}", .{ targetImage.width, targetImage.height });

    rl.initWindow(targetImage.width, targetImage.height, "Pale");
    defer rl.closeWindow();

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rng = prng.random();
    const mutation = CombinedMutation.init(&rng, targetImage.width, targetImage.height);

    var canvasImage = targetImage.copy();
    defer canvasImage.unload();
    const texture = try rl.Texture2D.fromImage(canvasImage);
    defer texture.unload();

    var buffer: [64]u8 = undefined;
    var counter: i32 = 0;
    const maxError: u64 = @intCast(targetImage.width * targetImage.height * 256 * 3);
    var oldDiff: u64 = maxError;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const start = std.time.microTimestamp();
    const totalTime = std.time.us_per_min;

    while (!rl.windowShouldClose()) {
        if (std.time.microTimestamp() - start > totalTime) {
            break;
        }
        // Update
        counter += 1;

        var oldSolution = solution.clone(alloc) catch |err| {
            std.log.err("Error allocating tmp solution ({})", .{err});
            return;
        };
        mutation.mutate(&solution);

        const diff = try EvalImageNaive(&targetImage, &canvasImage, &solution);
        if (diff <= oldDiff) {
            oldSolution.deinit(alloc);
            oldDiff = diff;
            rl.updateTexture(texture, canvasImage.data);
        } else {
            solution.deinit(alloc);
            solution = oldSolution;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.drawTexture(texture, 0, 0, .white);

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Counter: {}", .{counter});
            rl.drawText(text, 10, 10, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "Fitness: {}", .{oldDiff});
            rl.drawText(text, 10, 40, 20, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "FPS:     {}", .{rl.getFPS()});
            rl.drawText(text, 10, 70, 20, .light_gray);
        }

        {
            const text = try std.fmt.bufPrintZ(&buffer, "Rects:   {}", .{solution.data.items.len});
            rl.drawText(text, 10, 100, 20, .light_gray);
        }
    }
    const end = std.time.microTimestamp();
    const totalSeconds = @as(f64, @floatFromInt(end - start)) / 1_000_000.0;
    try stdout.print("Iterations: {}\n", .{counter});
    try stdout.print("Seconds: {}\n", .{totalSeconds});
    try stdout.print("Iters/second: {}\n", .{@as(f64, @floatFromInt(counter)) / totalSeconds});
    try stdout.print("Normalized error: {}\n", .{@as(f64, @floatFromInt(oldDiff)) / @as(f64, @floatFromInt(maxError))});
    try stdout.flush();

    try DrawSolution(&solution, &canvasImage);
    _ = canvasImage.exportToFile("naive.png");
}
