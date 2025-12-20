const std = @import("std");
const Solution = @import("solution.zig").Solution;
const Rectangle = @import("graphics.zig").Rectangle;
const Color = @import("graphics.zig").Color;

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
        var color = Color.fromInt(self.rng.int(u32));
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
            const index = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
            solution.addUnevaluated(solution.data.items[index].rect);
            solution.data.items[index] = .{
                .rect = rect,
                .color = color,
            };
        } else {
            const index = self.rng.intRangeAtMost(usize, 0, solution.data.items.len);
            solution.data.insertAssumeCapacity(index, .{
                .rect = rect,
                .color = color,
            });
        }
    }
};

const ResizeMoveMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ResizeMoveMutation {
        return ResizeMoveMutation{ .rng = rng };
    }

    pub fn mutateIndexed(self: ResizeMoveMutation, solution: *Solution, index: usize) void {
        const moveDiffRange = 10;
        const dxBefore = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const dyBefore = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const dxAfter = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);
        const dyAfter = self.rng.intRangeAtMost(i32, -moveDiffRange, moveDiffRange);

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

    pub fn mutate(self: ResizeMoveMutation, solution: *Solution) void {
        if (solution.data.items.len == 0) {
            return;
        }

        const index = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
        self.mutateIndexed(solution, index);
    }
};

const ColorMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) ColorMutation {
        return ColorMutation{ .rng = rng };
    }

    pub fn mutateIndexed(self: ColorMutation, solution: *Solution, index: usize) void {
        const colorDiffRange = 50;
        const dr = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const dg = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);
        const db = self.rng.intRangeAtMost(i32, -colorDiffRange, colorDiffRange);

        const item = &solution.data.items[index];
        solution.addUnevaluated(item.rect);
        const color = &item.color;
        color.r = @intCast(@mod(@as(i32, item.color.r) + dr, 256));
        color.g = @intCast(@mod(@as(i32, item.color.g) + dg, 256));
        color.b = @intCast(@mod(@as(i32, item.color.b) + db, 256));
        std.log.debug("Color mutation: x={} y={} b={}", .{ color.r, color.g, color.b });
    }

    pub fn mutate(self: ColorMutation, solution: *Solution) void {
        if (solution.data.items.len == 0) {
            return;
        }
        const index = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
        self.mutateIndexed(solution, index);
    }
};

const DeleteMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) DeleteMutation {
        return DeleteMutation{ .rng = rng };
    }

    pub fn mutate(self: DeleteMutation, solution: *Solution) void {
        if (solution.data.items.len == 0) {
            return;
        }
        const index = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
        const item = solution.data.orderedRemove(index);
        solution.addUnevaluated(item.rect);
        std.log.debug("Delete mutation: i={}", .{index});
    }
};

const SwapMutation = struct {
    rng: *const std.Random = undefined,

    pub fn init(rng: *const std.Random) SwapMutation {
        return SwapMutation{ .rng = rng };
    }

    pub fn mutate(self: SwapMutation, solution: *Solution) void {
        if (solution.data.items.len == 0) {
            return;
        }
        // Removing a rectangle, and moving it back or forward is better for
        // the evaluator then just swapping 2 rectangles
        // In the case you just move the position of a single rectangle, we
        // just have to re-evaluate its bounding rect, while with 2 rectangles
        // we would have to evaluate the min-max box of the 2 swapped rectangles
        const indexSrc = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
        const indexDest = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
        const item = solution.data.orderedRemove(indexSrc);
        solution.data.insertAssumeCapacity(indexDest, item);
        solution.addUnevaluated(item.rect);
        std.log.debug("Delete mutation: src_i={} dest_i={}", .{ indexSrc, indexDest });
    }
};

const SplitAndMutateMutation = struct {
    rng: *const std.Random = undefined,
    resizeMoveMutation: ResizeMoveMutation,
    colorMutation: ColorMutation,

    pub fn init(rng: *const std.Random) SplitAndMutateMutation {
        return SplitAndMutateMutation{
            .rng = rng,
            .resizeMoveMutation = ResizeMoveMutation.init(rng),
            .colorMutation = ColorMutation.init(rng),
        };
    }

    pub fn mutate(self: SplitAndMutateMutation, solution: *Solution) void {
        if (solution.data.items.len == 0) {
            return;
        }
        if (solution.data.capacity == solution.data.items.len) {
            return;
        }

        const index = self.rng.intRangeLessThan(usize, 0, solution.data.items.len);
        var item1 = &solution.data.items[index];

        // Anything less is not worth splitting
        // When this is bound to 2 it leads to a weird behavior where
        // everything works normal, until the number of rectangles explodes
        if (item1.rect.height <= 10 or item1.rect.width <= 10) {
            return;
        }

        solution.data.insertAssumeCapacity(index + 1, item1.*);
        var item2 = &solution.data.items[index + 1];

        if (self.rng.boolean()) {
            // Split along x axis
            const splitAt = self.rng.intRangeLessThan(i32, 1, item1.rect.width);
            item1.rect.width = splitAt;
            item2.rect.width -= splitAt;
            item2.rect.x += splitAt;
        } else {
            // Split along y axis
            const splitAt = self.rng.intRangeLessThan(i32, 1, item1.rect.height);
            item1.rect.height = splitAt;
            item2.rect.height -= splitAt;
            item2.rect.y += splitAt;
        }

        const modifyIndex = self.rng.intRangeAtMost(usize, index, index + 1);
        if (self.rng.boolean()) {
            self.colorMutation.mutateIndexed(solution, modifyIndex);
        } else {
            self.resizeMoveMutation.mutateIndexed(solution, modifyIndex);
        }
    }
};

const MutationUnion = union(enum) {
    add: AddMutation,
    color: ColorMutation,
    resizeMove: ResizeMoveMutation,
    delete: DeleteMutation,
    swap: SwapMutation,
    splitAndMutate: SplitAndMutateMutation,

    pub fn mutate(self: MutationUnion, solution: *Solution) void {
        switch (self) {
            inline else => |case| return case.mutate(solution),
        }
    }
};

pub const CombinedMutation = struct {
    mutations: [6]MutationUnion,
    weights: [6]i32,
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
                .{
                    .splitAndMutate = SplitAndMutateMutation.init(rng),
                },
            },
            .weights = .{
                50, 50, 100, 10, 20, 5,
            },
        };
    }

    pub fn mutate(self: CombinedMutation, solution: *Solution) void {
        const index = self.rng.weightedIndex(i32, &self.weights);
        self.mutations[index].mutate(solution);
    }
};
