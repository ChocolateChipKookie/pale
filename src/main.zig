const std = @import("std");

const rl = @import("raylib");

pub fn main() anyerror!void {
    const image = try rl.Image.init("earring.png");
    std.log.info("Image size: {d}x{d}", .{ image.width, image.height });

    rl.initWindow(image.width, image.height, "Pale");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    // const texture = try rl.Texture2D.init("earring.png");

    var renderTexture = try rl.RenderTexture2D.init(image.width, image.height);
    {
        renderTexture.begin();
        defer renderTexture.end();
        rl.clearBackground(.blue);
        rl.drawCircle(50, 50, 50, .green);
    }
    var textureImage = try rl.Image.fromTexture(renderTexture.texture);

    for (0..500) |x| {
        for (0..500) |y| {
            textureImage.drawPixel(@intCast(x), @intCast(y), image.getColor(@intCast(x), @intCast(y)));
        }
    }

    textureImage.drawCircle(200, 200, 20, .pink);

    const finalTexture = try rl.Texture2D.fromImage(textureImage);

    var buffer: [16]u8 = undefined;

    var counter: u8 = 0;
    while (!rl.windowShouldClose()) {
        // Update
        counter +%= 1;
        const color = rl.Color.init(counter, 0, 0, counter);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        rl.drawTexture(finalTexture, 0, 0, .white);
        rl.drawRectangle(100, 100, 100, 100, color);
        const text = try std.fmt.bufPrintZ(&buffer, "{}", .{counter});
        rl.drawText(text, 190, 200, 40, .light_gray);
    }
}
