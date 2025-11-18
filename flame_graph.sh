#!/bin/bash

# Assumes FlameGraph checked out next to this repo
zig build --release=fast
perf record -g -F 999 -- ./zig-out/bin/pale
perf script > perf.out
../FlameGraph/stackcollapse-perf.pl perf.out > perf.folded
../FlameGraph/flamegraph.pl perf.folded > perf.svg
rm perf.data perf.out perf.folded
