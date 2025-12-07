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
        std.log.debug("Add mutation: x={} y={} width={} height={}", .{ rect.x, rect.y, rect.width, rect.height });
        solution.addUnevaluated(rect);

        if (solution.data.capacity == solution.data.items.len) {
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

const ResizeMoveMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ResizeMoveMutation {
        var res = ResizeMoveMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(self: ResizeMoveMutation, solution: *Solution) void {
        if (solution.*.data.items.len == 0) {
            return;
        }

        const moveDiffRange = 10;
        const dxBefore = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const dyBefore = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const dxAfter = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const dyAfter = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);

        const rect = &solution.data.items[index].rect;
        solution.addUnevaluated(rect.*);
        rect.x += dxBefore;
        rect.y += dyBefore;
        rect.width += dxAfter - dxBefore;
        rect.height += dyAfter - dyBefore;
        rect.width = @max(1, rect.width);
        rect.height = @max(1, rect.height);
        solution.addUnevaluated(rect.*);
        std.log.debug("Resize mutation: x={} y={} width={} height={}", .{ rect.x, rect.y, rect.width, rect.height });
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
        const colorDiffRange = 50;
        const dr = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const dg = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const db = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);

        const item = &solution.*.data.items[index];
        solution.addUnevaluated(item.rect);
        const color = &item.color;
        color.r = @intCast(@mod(@as(i32, item.color.r) + dr, 256));
        color.g = @intCast(@mod(@as(i32, item.color.g) + dg, 256));
        color.b = @intCast(@mod(@as(i32, item.color.b) + db, 256));
        std.log.debug("Color mutation: x={} y={} b={}", .{ color.r, color.g, color.b });
    }
};

const DeleteMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) DeleteMutation {
        var res = DeleteMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(self: DeleteMutation, solution: *Solution) void {
        if (solution.*.data.items.len == 0) {
            return;
        }
        const index = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);
        const item = solution.data.orderedRemove(index);
        solution.addUnevaluated(item.rect);
        std.log.debug("Delete mutation: i={}", .{index});
    }
};

const SwapMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) SwapMutation {
        var res = SwapMutation{};
        res.rng = rng;
        return res;
    }

    pub fn mutate(self: SwapMutation, solution: *Solution) void {
        if (solution.*.data.items.len == 0) {
            return;
        }
        // Removing a rectangle, and moving it back or forward is better for
        // the evaluator then just swapping 2 rectangles
        // In the case you just move the position of a single rectangle, we
        // just have to re-evaluate its bounding rect, while with 2 rectangles
        // we would have to evaluate the min-max box of the 2 swapped rectangles
        const indexSrc = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);
        const indexDest = self.rng.intRangeLessThan(usize, 0, solution.*.data.items.len);
        const item = solution.data.orderedRemove(indexSrc);
        solution.data.insertAssumeCapacity(indexDest, item);
        solution.addUnevaluated(item.rect);
        std.log.debug("Delete mutation: src_i={} dest_i={}", .{ indexSrc, indexDest });
    }
};

const MutationUnion = union(enum) {
    add: AddMutation,
    color: ColorMutation,
    resizeMove: ResizeMoveMutation,
    delete: DeleteMutation,
    swap: SwapMutation,

    pub fn mutate(self: MutationUnion, solution: *Solution) void {
        switch (self) {
            inline else => |case| return case.mutate(solution),
        }
    }
};

pub const CombinedMutation = struct {
    mutations: [5]MutationUnion,
    weights: [5]i32,
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
                    .resizeMove = ResizeMoveMutation.init(rng),
                },
                .{
                    .delete = DeleteMutation.init(rng),
                },
                .{
                    .swap = SwapMutation.init(rng),
                },
            },
            .weights = .{
                10, 10, 20, 1, 2,
            },
        };
    }

    pub fn mutate(self: CombinedMutation, solution: *Solution) void {
        const index = self.rng.weightedIndex(i32, &self.weights);
        self.mutations[index].mutate(solution);
    }
};
