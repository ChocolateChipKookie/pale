const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn fromInt(color: u32) Color {
        return .{
            .r = @intCast((color >> 24) & 0xff),
            .g = @intCast((color >> 16) & 0xff),
            .b = @intCast((color >> 8) & 0xff),
            .a = @intCast((color >> 0) & 0xff),
        };
    }

    pub fn format(
        self: Color,
        writer: anytype,
    ) !void {
        try writer.print("Color(.r={d}, .g={d}, .b={d}, .a={d})", .{
            @as(i32, @intCast(self.r)),
            @as(i32, @intCast(self.g)),
            @as(i32, @intCast(self.b)),
            @as(i32, @intCast(self.a)),
        });
    }

    pub const black: Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
};

pub const Rectangle = struct {
    // Using signed integers for ease of use
    x: i32 = 0,
    y: i32 = 0,
    // Width and height < 0 are considered to be 0
    width: i32 = 0,
    height: i32 = 0,

    pub fn intersects(self: Rectangle, other: Rectangle) bool {
        return self.x <= other.x + other.width and
            self.x + self.width >= other.x and
            self.y <= other.y + other.height and
            self.y + self.height >= other.y;
    }
};

pub const Canvas = struct {
    data: []Color,
    width: usize,
    height: usize,

    pub fn init(alloc: std.mem.Allocator, width: usize, height: usize) !Canvas {
        return Canvas{
            .data = try alloc.alloc(Color, width * height),
            .width = width,
            .height = height,
        };
    }

    pub fn clone(self: Canvas, alloc: std.mem.Allocator) !Canvas {
        return Canvas{
            .data = try alloc.dupe(Color, self.data),
            .width = self.width,
            .height = self.height,
        };
    }

    pub fn deinit(self: Canvas, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
    }

    pub fn clear(self: Canvas, color: Color) void {
        @memset(self.data, color);
    }

    pub fn drawRectangle(self: Canvas, rect: Rectangle, color: Color) void {
        const x_start: usize = @intCast(@max(0, @min(rect.x, self.width)));
        const x_end: usize = @intCast(@max(0, @min(rect.x + rect.width, @as(i32, @intCast(self.width)))));
        const y_start: usize = @intCast(@max(0, @min(rect.y, self.height)));
        const y_end: usize = @intCast(@max(0, @min(rect.y + rect.height, @as(i32, @intCast(self.height)))));
        for (y_start..y_end) |y| {
            const row_start = y * self.width;
            const row = self.data[(row_start + x_start)..(row_start + x_end)];
            @memset(row, color);
        }
    }
};

test "Init and deinit Canvas" {
    const gpa = std.testing.allocator;
    const image = try Canvas.init(gpa, 3, 4);
    defer image.deinit(gpa);
    try std.testing.expect(image.data.len == 12);
    try std.testing.expect(image.width == 3);
    try std.testing.expect(image.height == 4);
    const uintData: []u8 = @ptrCast(image.data);
    try std.testing.expect(uintData.len == 48);
}

test "Clear canvas" {
    const gpa = std.testing.allocator;
    const image = try Canvas.init(gpa, 4, 5);
    defer image.deinit(gpa);

    image.clear(.white);
    for (image.data) |color| {
        try std.testing.expectEqual(color, Color.white);
    }

    image.clear(.black);
    for (image.data) |color| {
        try std.testing.expectEqual(color, Color.black);
    }
}

test "Draw rect" {
    const gpa = std.testing.allocator;
    const image = try Canvas.init(gpa, 3, 4);
    defer image.deinit(gpa);

    {
        image.clear(.black);
        const rect: Rectangle = .{ .x = 1, .y = 1, .width = 1, .height = 2 };
        image.drawRectangle(rect, .white);

        const expected_pixels = [_]Color{
            .black, .black, .black,
            .black, .white, .black,
            .black, .white, .black,
            .black, .black, .black,
        };
        try std.testing.expectEqualSlices(Color, image.data, &expected_pixels);
    }
    {
        image.clear(.black);
        const rect: Rectangle = .{ .x = -1, .y = -1, .width = 2, .height = 2 };
        image.drawRectangle(rect, .white);

        const expected_pixels = [_]Color{
            .white, .black, .black,
            .black, .black, .black,
            .black, .black, .black,
            .black, .black, .black,
        };
        try std.testing.expectEqualSlices(Color, image.data, &expected_pixels);
    }
    {
        image.clear(.black);
        const rect: Rectangle = .{ .x = -1, .y = -1, .width = 20, .height = 20 };
        image.drawRectangle(rect, .white);

        const expected_pixels = [_]Color{
            .white, .white, .white,
            .white, .white, .white,
            .white, .white, .white,
            .white, .white, .white,
        };
        try std.testing.expectEqualSlices(Color, image.data, &expected_pixels);
    }
    {
        image.clear(.black);
        const rect: Rectangle = .{ .x = 2, .y = 2, .width = 1, .height = 2 };
        image.drawRectangle(rect, .white);

        const expected_pixels = [_]Color{
            .black, .black, .black,
            .black, .black, .black,
            .black, .black, .white,
            .black, .black, .white,
        };
        try std.testing.expectEqualSlices(Color, image.data, &expected_pixels);
    }
    {
        image.clear(.black);
        const rect: Rectangle = .{ .x = 2, .y = 2, .width = 5, .height = 5 };
        image.drawRectangle(rect, .white);

        const expected_pixels = [_]Color{
            .black, .black, .black,
            .black, .black, .black,
            .black, .black, .white,
            .black, .black, .white,
        };
        try std.testing.expectEqualSlices(Color, image.data, &expected_pixels);
    }
    {
        image.clear(.black);
        const rect: Rectangle = .{ .x = 2, .y = 2, .width = 0, .height = 0 };
        image.drawRectangle(rect, .white);

        const expected_pixels = [_]Color{
            .black, .black, .black,
            .black, .black, .black,
            .black, .black, .black,
            .black, .black, .black,
        };
        try std.testing.expectEqualSlices(Color, image.data, &expected_pixels);
    }
}

test "Color.fromInt" {
    {
        const color = Color.fromInt(255);
        try std.testing.expectEqual(color, Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
    }
    {
        const color = Color.fromInt(234 << 8);
        try std.testing.expectEqual(color, Color{ .r = 0, .g = 0, .b = 234, .a = 0 });
    }
    {
        const color = Color.fromInt(123 << 16);
        try std.testing.expectEqual(color, Color{ .r = 0, .g = 123, .b = 0, .a = 0 });
    }
    {
        const color = Color.fromInt(12 << 24);
        try std.testing.expectEqual(color, Color{ .r = 12, .g = 0, .b = 0, .a = 0 });
    }
    {
        const color = Color.fromInt(0);
        try std.testing.expectEqual(color, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    }
    {
        const color = Color.fromInt(0x12345678);
        try std.testing.expectEqual(color, Color{ .r = 18, .g = 52, .b = 86, .a = 120 });
    }
}
