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

## Progress

Part of this project will be optimizing the both the algorithm, but also the efficiency of evaluating the solutions, and the program as a whole.

The measurements are not going to be too precise, as they will be run on my computer locally, and not in some kind of reproducable environment. The problem is highly dependent on randomness, so a streak of favorable rolls can yield a much fitter solution.

To counter the fact that the evaluations are going to be run on my laptop locally, I will make sure to run the evaluation with the laptop plugged in, with performance mode enabled, and with only the single terminal open.

To counter the randomness factor I will re-run the process 10 times and take the mean of all the values.

Attempt | Avg. time run | Avg. iterations | Avg. iter/sec | Avg. normalized error | Result
--- | --- | --- | --- | --- | --- 
Naive mutations and evaluation | 60.03 s | 10567 | 176.1 | 0.08733 | <img src="./resources/naive.png" height="150">
Same naive, but load all the pixels at once | 60.03 s | 15070 | 251.1 | 0.07870 | <img src="./resources/naive_load.png" height="150">
Naive, but with rate limited frame rendering, meaning more time for evaluation | 60.01 s | 15871 | 264.4 | 0.07797 | <img src="./resources/naive_rate_limited.png" height="150">
Evaluating only changed parts of the solution | 60.02 s | 52803 | 879.7 | 0.05097 | <img src="./resources/eval_region.png" height="150">
Replace image.clearBackground with image.drawRectangle | 60.02 s | 576317 | 9602 | 0.04047 | <img src="./resources/eval_rect.png" height="150">
Remove upper bound for number of rects, and introduce deletion pressure | 60.02 s | 1044038 | 17394.55 | 0.03586 | <img src="./resources/unbound_delete.png" height="150">
Add swap mutation | 60.02 s | 993655 | 16555 | 0.03535 | <img src="./resources/unbound_swap.png" height="150">
Pull texture update out of busy loop | 60.02 s | 1109911 | 18493 | 0.03463 | <img src="./resources/tex_update_out_of_loop.png" height="150">
