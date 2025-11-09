const std = @import("std");

const rl = @import("raylib");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "Pale");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var counter: u8 = 0;
    while (!rl.windowShouldClose()) {
        // Update
        counter +%= 1;
        const color = rl.Color.init(counter, 0, 0, counter);

        // Draw
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        rl.drawRectangle(100, 100, 100, 100, color);
        rl.drawText("Raylib window", 190, 200, 20, .light_gray);
    }
}
