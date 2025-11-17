const std = @import("std");
const rl = @import("raylib");
const Solution = @import("solution.zig").Solution;
const Rectangle = @import("solution.zig").Rectangle;

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

pub const CombinedMutation = struct {
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
