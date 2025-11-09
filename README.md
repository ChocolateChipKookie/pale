# Pale

Experiment project for testing out zig prior to doing some more serious development in it.

The goal for the project (except learning some zig) is to make a genetic algorithm that will try to mimic an image with some shape.

Ideally it will have a graphical progress tracker, and in the best of all worlds runnable in the browser.

## Notes

Because the project relies on raylib, and raylib in turn has some system deps, you will need to install those:

```
# apt update
# apt install libx11-dev libxext-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev libxfixes-dev libxrender-dev libgl1-mesa-dev libglu1-mesa-dev
```

