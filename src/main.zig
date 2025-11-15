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
        std.log.info("Add mutation", .{});

        const x = self.rng.intRangeAtMost(i32, 0, self.imageWidth);
        const y = self.rng.intRangeAtMost(i32, 0, self.imageHeight);
        const dx = self.rng.intRangeAtMost(i32, -20, 20);
        const dy = self.rng.intRangeAtMost(i32, -20, 20);
        const color = rl.Color.fromInt(self.rng.int(u32));

        solution.*.data.appendAssumeCapacity(.{
            .x = @min(x, x + dx),
            .y = @min(y, y + dy),
            .width = @intCast(@abs(dx)),
            .height = @intCast(@abs(dy)),
            .color = color,
        });
    }
};

const MoveMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) MoveMutation {
        var res = MoveMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(_: MoveMutation, _: *Solution) void {
        std.log.info("Move mutation", .{});
    }
};

const ResizeMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ResizeMutation {
        var res = ResizeMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(_: ResizeMutation, _: *Solution) void {
        std.log.info("Resize mutation", .{});
    }
};

const ColorMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ColorMutation {
        var res = ColorMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(_: ColorMutation, _: *Solution) void {
        std.log.info("Color mutation", .{});
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

fn DrawSolution(solution: Solution, canvas: *rl.Image) !void {
    canvas.clearBackground(.black);
    for (solution.data.items) |rect| {
        canvas.drawRectangle(rect.x, rect.y, rect.width, rect.height, rect.color);
    }
}

fn EvalImageNaive(target: *const rl.Image, canvas: *const rl.Image) !u64 {
    var total: u64 = 0;

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

fn EvalImageNaiveLoadColors(target: *const rl.Image, canvas: *const rl.Image) !u64 {
    var total: u64 = 0;

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var solution = Solution.init(alloc, 1000) catch |err| {
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

    var buffer: [16]u8 = undefined;
    var counter: i32 = 0;
    var oldDiff: u64 = @intCast(targetImage.width * targetImage.height * 256 * 3);

    while (!rl.windowShouldClose()) {
        // Update
        counter += 1;

        const oldSolution = solution;
        mutation.mutate(&solution);

        try DrawSolution(solution, &canvasImage);
        const diff = try EvalImageNaiveLoadColors(&targetImage, &canvasImage);
        if (diff <= oldDiff) {
            oldDiff = diff;
            rl.updateTexture(texture, canvasImage.data);
        } else {
            solution = oldSolution;
        }

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.drawTexture(texture, 0, 0, .white);

        {
            const text = try std.fmt.bufPrintZ(&buffer, "{}", .{counter});
            rl.drawText(text, 190, 200, 40, .light_gray);
        }

        {
            const text = try std.fmt.bufPrintZ(&buffer, "{}", .{rl.getFPS()});
            rl.drawText(text, 100, 100, 40, .light_gray);
        }
        {
            const text = try std.fmt.bufPrintZ(&buffer, "{}", .{oldDiff});
            rl.drawText(text, 100, 400, 40, .light_gray);
        }
    }
}
